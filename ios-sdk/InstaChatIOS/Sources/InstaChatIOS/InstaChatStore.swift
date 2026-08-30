import Foundation

@MainActor
final class InstaChatStore: ObservableObject {
  @Published private(set) var rooms: [InstaChatRoom] = []
  @Published private(set) var messagesByRoom: [String: [InstaChatMessage]] = [:]
  @Published private(set) var isLoadingRooms = false
  @Published private(set) var isLoadingMessages = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var typingRoomIDs: Set<String> = []
  @Published private(set) var deliveryStatesByMessageID: [String: OutgoingMessageDeliveryState] = [:]

  let configuration: InstaChatConfiguration
  private let client: any InstaChatClientProtocol
  private let pendingStore: PendingOutgoingMessageStore
  private var pendingOutgoingByMessageID: [String: PendingOutgoingMessage] = [:]
  private var realtimeTask: Task<Void, Never>?
  private var isRealtimeListening = false
  private var activeRoomID: String?

  init(
    configuration: InstaChatConfiguration,
    client: (any InstaChatClientProtocol)? = nil,
    pendingStore: PendingOutgoingMessageStore? = nil
  ) {
    self.configuration = configuration
    self.client = client ?? InstaChatClient(configuration: configuration)
    self.pendingStore = pendingStore ?? PendingOutgoingMessageStore(configuration: configuration)
    restorePendingMessages()
  }

  deinit {
    realtimeTask?.cancel()
    client.disconnect()
  }

  func start() {
    guard !isRealtimeListening else {
      return
    }
    isRealtimeListening = true

    let realtimeClient = client
    realtimeTask = Task { [weak self, realtimeClient] in
      for await event in realtimeClient.realtimeEvents() {
        guard let self else {
          realtimeClient.disconnect()
          return
        }
        self.applyRealtimeEvent(event)
      }

      guard let self else {
        return
      }
      self.isRealtimeListening = false
      self.realtimeTask = nil
    }
  }

  func refreshAfterForeground() async {
    start()
    client.refreshRealtimeConnection()
    await loadRooms()
    if let activeRoomID {
      await loadMessages(roomID: activeRoomID)
    }
  }

  func loadRooms() async {
    isLoadingRooms = true
    errorMessage = nil
    do {
      let fetchedRooms = try await client.getRooms()
      rooms = mergeRoomList(fetchedRooms)
    } catch {
      errorMessage = InstaChatSendFailure.actionMessage(for: error, language: configuration.language)
    }
    isLoadingRooms = false
  }

  func setActiveRoom(_ roomID: String?) {
    activeRoomID = roomID
    guard let roomID else {
      return
    }
    updateRoom(id: roomID) { room in
      room.unreadCount = 0
    }
  }

  func loadMessages(roomID: String) async {
    isLoadingMessages = true
    errorMessage = nil
    do {
      let page = try await client.getMessages(roomID: roomID, limit: configuration.historyLimit, cursor: nil)
      mergeFetchedMessages(page.messages, roomID: roomID)
    } catch {
      errorMessage = InstaChatSendFailure.actionMessage(for: error, language: configuration.language)
    }
    isLoadingMessages = false
  }

  func sendText(_ text: String, roomID: String) async {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
      return
    }

    let optimisticMessage = InstaChatMessage(
      id: "local-\(UUID().uuidString)",
      roomID: roomID,
      senderID: configuration.user.id,
      senderName: configuration.user.name,
      content: trimmedText,
      type: .text,
      createdAt: Date()
    )
    await enqueueAndSend(message: optimisticMessage, payload: .text(trimmedText))
  }

  func sendLocation(_ location: InstaChatLocation, roomID: String) async {
    let optimisticMessage = InstaChatMessage(
      id: "local-\(UUID().uuidString)",
      roomID: roomID,
      senderID: configuration.user.id,
      senderName: configuration.user.name,
      content: (try? String(data: JSONEncoder().encode(location), encoding: .utf8)) ?? "",
      type: .location,
      createdAt: Date(),
      location: location
    )
    await enqueueAndSend(message: optimisticMessage, payload: .location(location))
  }

  func sendAttachment(fileURL: URL, roomID: String, contentType: String? = nil) async {
    let messageID = "local-\(UUID().uuidString)"
    do {
      let localFileURL = try await pendingStore.preserveFile(at: fileURL, messageID: messageID)
      let resolvedContentType = contentType ?? MimeTypeResolver.mimeType(for: localFileURL)
      let attachmentType = MimeTypeResolver.attachmentType(for: resolvedContentType)
      let localAttachment = InstaChatAttachment(
        id: "local-attachment-\(UUID().uuidString)",
        fileName: fileURL.lastPathComponent.isEmpty ? configuration.localizer.text("Attachment") : fileURL.lastPathComponent,
        contentType: resolvedContentType,
        type: attachmentType,
        fileSize: try? localFileURL.fileSize,
        url: localFileURL
      )
      let optimisticMessage = InstaChatMessage(
        id: messageID,
        roomID: roomID,
        senderID: configuration.user.id,
        senderName: configuration.user.name,
        content: localAttachment.fileName,
        type: attachmentType == .image ? .image : .file,
        createdAt: Date(),
        attachment: localAttachment
      )
      await enqueueAndSend(
        message: optimisticMessage,
        payload: .attachment(
          localFileURL: localFileURL,
          contentType: resolvedContentType,
          uploadedAttachment: nil
        )
      )
    } catch {
      errorMessage = InstaChatSendFailure.userFacing(
        for: error,
        attachmentType: MimeTypeResolver.attachmentType(for: contentType ?? MimeTypeResolver.mimeType(for: fileURL)),
        language: configuration.language
      ).message
    }
  }

  func sendAttachments(_ files: [PickedMediaFile], roomID: String) async {
    for file in files {
      await sendAttachment(fileURL: file.url, roomID: roomID, contentType: file.contentType)
    }
  }

  func sendTyping(roomID: String, isTyping: Bool) {
    Task {
      try? await client.sendTyping(roomID: roomID, isTyping: isTyping)
    }
  }

  func reportError(_ message: String) {
    errorMessage = message
  }

  func reportError(_ error: Error) {
    errorMessage = InstaChatSendFailure.actionMessage(for: error, language: configuration.language)
  }

  func dismissError() {
    errorMessage = nil
  }

  func messages(for roomID: String) -> [InstaChatMessage] {
    messagesByRoom[roomID] ?? []
  }

  func deliveryState(for messageID: String) -> OutgoingMessageDeliveryState? {
    deliveryStatesByMessageID[messageID]
  }

  func retryMessage(messageID: String) async {
    guard var pending = pendingOutgoingByMessageID[messageID] else {
      return
    }
    pending.failure = nil
    pendingOutgoingByMessageID[messageID] = pending
    deliveryStatesByMessageID[messageID] = .sending
    persistPendingMessages()
    await performSend(messageID: messageID)
  }

  func room(id roomID: String) -> InstaChatRoom? {
    rooms.first { $0.id == roomID }
  }

  func applyRealtimeEvent(_ event: InstaChatRealtimeEvent) {
    switch event {
    case let .message(message):
      let incrementsUnread = message.senderID != configuration.user.id && message.roomID != activeRoomID
      upsert(message, updateRoomPreview: true, incrementsUnread: incrementsUnread)
    case let .typing(roomID, _, isTyping):
      if isTyping {
        typingRoomIDs.insert(roomID)
      } else {
        typingRoomIDs.remove(roomID)
      }
    }
  }

  private func mergeFetchedMessages(_ fetchedMessages: [InstaChatMessage], roomID: String) {
    var messages = messagesByRoom[roomID] ?? []

    for fetchedMessage in fetchedMessages {
      if let existingIndex = messages.firstIndex(where: { $0.id == fetchedMessage.id }) {
        messages[existingIndex] = fetchedMessage
      } else if let localEchoIndex = localEchoIndex(for: fetchedMessage, in: messages) {
        reconcileCachedMedia(from: messages[localEchoIndex], to: fetchedMessage)
        resolvePendingMessage(messageID: messages[localEchoIndex].id)
        messages[localEchoIndex] = fetchedMessage
      } else {
        messages.append(fetchedMessage)
      }
    }

    messages.sort { $0.createdAt < $1.createdAt }
    messagesByRoom[roomID] = messages
    if let latestMessage = messages.last {
      updateRoomPreview(with: latestMessage, incrementsUnread: false)
    }
  }

  private func upsert(_ message: InstaChatMessage, updateRoomPreview: Bool, incrementsUnread: Bool) {
    var messages = messagesByRoom[message.roomID] ?? []

    if let existingIndex = messages.firstIndex(where: { $0.id == message.id }) {
      messages[existingIndex] = message
    } else if let localEchoIndex = localEchoIndex(for: message, in: messages) {
      reconcileCachedMedia(from: messages[localEchoIndex], to: message)
      resolvePendingMessage(messageID: messages[localEchoIndex].id)
      messages[localEchoIndex] = message
    } else {
      messages.append(message)
    }

    messages.sort { $0.createdAt < $1.createdAt }
    messagesByRoom[message.roomID] = messages
    if updateRoomPreview {
      self.updateRoomPreview(with: message, incrementsUnread: incrementsUnread)
    }
  }

  func append(_ message: InstaChatMessage, replacingLocalEcho: Bool, updateRoomPreview: Bool = true, incrementsUnread: Bool = false) {
    var messages = messagesByRoom[message.roomID] ?? []
    if messages.contains(where: { $0.id == message.id }) {
      return
    }

    if replacingLocalEcho, let index = localEchoIndex(for: message, in: messages) {
      messages[index] = message
    } else {
      messages.append(message)
    }

    messages.sort { $0.createdAt < $1.createdAt }
    messagesByRoom[message.roomID] = messages
    if updateRoomPreview {
      self.updateRoomPreview(with: message, incrementsUnread: incrementsUnread)
    }
  }

  private func localEchoIndex(for message: InstaChatMessage, in messages: [InstaChatMessage]) -> Int? {
    guard message.senderID == configuration.user.id else {
      return nil
    }

    let candidates = messages.indices.filter { index in
      let candidate = messages[index]
      guard candidate.id.hasPrefix("local-"), candidate.senderID == configuration.user.id else {
        return false
      }
      guard abs(candidate.createdAt.timeIntervalSince(message.createdAt)) < 300 else {
        return false
      }
      return candidate.localEchoKey == message.localEchoKey
    }

    guard message.attachment != nil else {
      return candidates.last
    }

    if let exactMatch = candidates.first(where: { index in
      guard let candidateAttachment = messages[index].attachment,
            let incomingAttachment = message.attachment else {
        return false
      }
      return candidateAttachment.id == incomingAttachment.id || candidateAttachment.url == incomingAttachment.url
    }) {
      return exactMatch
    }

    // Attachment echoes are emitted in send order. When the backend rewrites
    // both attachment ID and CDN URL, consume the oldest matching local row
    // instead of the previous last-match behavior that swapped media cells.
    return candidates.first
  }

  private func reconcileCachedMedia(from localMessage: InstaChatMessage, to backendMessage: InstaChatMessage) {
    guard let localAttachment = localMessage.attachment,
          let backendAttachment = backendMessage.attachment,
          localAttachment.type == backendAttachment.type else {
      return
    }

    Task {
      try? await AuthenticatedMediaCache.shared.rekeyCachedFile(
        from: localAttachment.url,
        sourceFileName: localAttachment.fileName,
        to: backendAttachment.url,
        destinationFileName: backendAttachment.fileName
      )
    }
  }

  private func enqueueAndSend(message: InstaChatMessage, payload: PendingOutgoingPayload) async {
    let pending = PendingOutgoingMessage(message: message, payload: payload, failure: nil)
    pendingOutgoingByMessageID[message.id] = pending
    deliveryStatesByMessageID[message.id] = .sending
    append(message, replacingLocalEcho: false, updateRoomPreview: true, incrementsUnread: false)
    persistPendingMessages()
    await performSend(messageID: message.id)
  }

  private func performSend(messageID: String) async {
    guard var pending = pendingOutgoingByMessageID[messageID] else {
      return
    }

    do {
      switch pending.payload {
      case let .text(text):
        try await client.sendText(text, roomID: pending.message.roomID)
      case let .location(location):
        try await client.sendLocation(location, roomID: pending.message.roomID)
      case let .attachment(localFileURL, contentType, existingAttachment):
        let uploadedAttachment: InstaChatAttachment
        if let existingAttachment {
          uploadedAttachment = existingAttachment
        } else {
          uploadedAttachment = try await client.uploadAttachment(
            fileURL: localFileURL,
            roomID: pending.message.roomID,
            contentType: contentType
          )
          if uploadedAttachment.type == .audio || uploadedAttachment.type == .video || uploadedAttachment.type == .image {
            try? await AuthenticatedMediaCache.shared.storeLocalFile(
              at: localFileURL,
              for: uploadedAttachment.url,
              fileName: uploadedAttachment.fileName
            )
          }
          pending.payload = .attachment(
            localFileURL: localFileURL,
            contentType: contentType,
            uploadedAttachment: uploadedAttachment
          )
          pending.message.attachment = uploadedAttachment
          pending.message.content = uploadedAttachment.fileName
          pendingOutgoingByMessageID[messageID] = pending
          updateMessage(pending.message)
          persistPendingMessages()
        }
        try await client.sendAttachment(
          uploadedAttachment,
          text: uploadedAttachment.fileName,
          roomID: pending.message.roomID
        )
      }

      resolvePendingMessage(messageID: messageID)
    } catch {
      let failure = InstaChatSendFailure.userFacing(for: error, attachmentType: pending.payload.attachmentType, language: configuration.language)
      pending.failure = failure
      pendingOutgoingByMessageID[messageID] = pending
      deliveryStatesByMessageID[messageID] = .failed(failure)
      persistPendingMessages()
    }
  }

  private func updateMessage(_ message: InstaChatMessage) {
    guard var messages = messagesByRoom[message.roomID],
          let index = messages.firstIndex(where: { $0.id == message.id }) else {
      return
    }
    messages[index] = message
    messagesByRoom[message.roomID] = messages
  }

  private func resolvePendingMessage(messageID: String) {
    guard let pending = pendingOutgoingByMessageID.removeValue(forKey: messageID) else {
      deliveryStatesByMessageID[messageID] = nil
      return
    }
    deliveryStatesByMessageID[messageID] = nil
    pendingStore.removePreservedFile(for: pending)
    persistPendingMessages()
  }

  private func restorePendingMessages() {
    for var pending in pendingStore.load() {
      let attachmentType = pending.payload.attachmentType
      let failure = pending.failure ?? .interrupted(attachmentType: attachmentType, language: configuration.language)
      pending.failure = failure
      pendingOutgoingByMessageID[pending.message.id] = pending
      deliveryStatesByMessageID[pending.message.id] = .failed(failure)
      append(pending.message, replacingLocalEcho: false, updateRoomPreview: true, incrementsUnread: false)
    }
    persistPendingMessages()
  }

  private func persistPendingMessages() {
    pendingStore.save(
      pendingOutgoingByMessageID.values.sorted { $0.message.createdAt < $1.message.createdAt }
    )
  }

  private func mergeRoomList(_ fetchedRooms: [InstaChatRoom]) -> [InstaChatRoom] {
    let localRoomsByID = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
    return fetchedRooms
      .map { fetchedRoom in
        var fetchedRoom = fetchedRoom
        fetchedRoom.subtitle = localizedRoomPreview(fetchedRoom.subtitle)
        guard let localRoom = localRoomsByID[fetchedRoom.id],
              let localUpdatedAt = localRoom.updatedAt,
              let fetchedUpdatedAt = fetchedRoom.updatedAt,
              localUpdatedAt > fetchedUpdatedAt else {
          return fetchedRoom
        }

        var mergedRoom = fetchedRoom
        mergedRoom.subtitle = localRoom.subtitle
        mergedRoom.updatedAt = localRoom.updatedAt
        mergedRoom.unreadCount = max(fetchedRoom.unreadCount, localRoom.unreadCount)
        return mergedRoom
      }
      .sorted(by: roomSort)
  }

  private func updateRoomPreview(with message: InstaChatMessage, incrementsUnread: Bool) {
    updateRoom(id: message.roomID) { room in
      room.subtitle = message.roomPreviewText(language: configuration.language)
      room.updatedAt = message.createdAt
      if message.senderID == configuration.user.id {
        room.unreadCount = 0
      } else if incrementsUnread {
        room.unreadCount += 1
      }
    }
  }

  private func updateRoom(id roomID: String, mutate: (inout InstaChatRoom) -> Void) {
    var updatedRooms = rooms
    if let index = updatedRooms.firstIndex(where: { $0.id == roomID }) {
      mutate(&updatedRooms[index])
    } else {
      var room = configuration.initialRoom?.id == roomID
        ? configuration.initialRoom!
        : InstaChatRoom(id: roomID, title: configuration.roomTitle ?? configuration.localizer.text("Chat"))
      mutate(&room)
      updatedRooms.append(room)
    }
    updatedRooms.sort(by: roomSort)
    rooms = updatedRooms
  }

  private func roomSort(_ left: InstaChatRoom, _ right: InstaChatRoom) -> Bool {
    switch (left.updatedAt, right.updatedAt) {
    case let (leftDate?, rightDate?):
      return leftDate > rightDate
    case (_?, nil):
      return true
    case (nil, _?):
      return false
    case (nil, nil):
      return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
  }

  private func localizedRoomPreview(_ preview: String?) -> String? {
    guard let preview else { return nil }
    switch preview {
    case "Message", "Location", "Photo", "Video", "Voice note", "File", "Online":
      return configuration.localizer.text(preview)
    default:
      return preview
    }
  }
}

extension InstaChatMessage {
  var localEchoKey: String {
    let attachmentKey = attachment.map {
      [$0.type.rawValue, $0.fileName, $0.contentType].joined(separator: ":")
    } ?? ""
    let locationKey = location.map { "\($0.latitude):\($0.longitude):\($0.name ?? "")" } ?? ""
    return [roomID, senderID, type.rawValue, content, attachmentKey, locationKey].joined(separator: "|")
  }

  func roomPreviewText(language: InstaChatLanguage = .devicePreferred) -> String {
    let strings = InstaChatLocalizer(language: language)
    switch type {
    case .text:
      return content.isEmpty ? strings.text("Message") : content
    case .image:
      return InstaChatAttachmentType.image.roomPreviewText(language: language)
    case .location:
      return strings.text("Location")
    case .file:
      return (attachment?.type ?? MimeTypeResolver.attachmentType(forFileName: content)).roomPreviewText(language: language)
    }
  }
}
