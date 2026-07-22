import Foundation

@MainActor
final class InstaChatStore: ObservableObject {
  @Published private(set) var rooms: [InstaChatRoom] = []
  @Published private(set) var messagesByRoom: [String: [InstaChatMessage]] = [:]
  @Published private(set) var isLoadingRooms = false
  @Published private(set) var isLoadingMessages = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var typingRoomIDs: Set<String> = []

  let configuration: InstaChatConfiguration
  private let client: InstaChatClient
  private var realtimeTask: Task<Void, Never>?

  init(configuration: InstaChatConfiguration, client: InstaChatClient? = nil) {
    self.configuration = configuration
    self.client = client ?? InstaChatClient(configuration: configuration)
  }

  deinit {
    realtimeTask?.cancel()
    client.disconnect()
  }

  func start() {
    guard realtimeTask == nil else {
      return
    }

    realtimeTask = Task { [weak self] in
      guard let self else {
        return
      }
      for await event in self.client.realtimeEvents() {
        self.applyRealtimeEvent(event)
      }
    }
  }

  func loadRooms() async {
    isLoadingRooms = true
    errorMessage = nil
    do {
      let fetchedRooms = try await client.getRooms()
      rooms = fetchedRooms
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoadingRooms = false
  }

  func loadMessages(roomID: String) async {
    isLoadingMessages = true
    errorMessage = nil
    do {
      let page = try await client.getMessages(roomID: roomID, limit: configuration.historyLimit)
      mergeFetchedMessages(page.messages, roomID: roomID)
    } catch {
      errorMessage = error.localizedDescription
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
    append(optimisticMessage, replacingLocalEcho: false)

    do {
      try await client.sendText(trimmedText, roomID: roomID)
    } catch {
      errorMessage = error.localizedDescription
    }
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
    append(optimisticMessage, replacingLocalEcho: false)

    do {
      try await client.sendLocation(location, roomID: roomID)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func sendAttachment(fileURL: URL, roomID: String, contentType: String? = nil) async {
    do {
      let attachment = try await client.uploadAttachment(fileURL: fileURL, roomID: roomID, contentType: contentType)
      let optimisticMessage = InstaChatMessage(
        id: "local-\(UUID().uuidString)",
        roomID: roomID,
        senderID: configuration.user.id,
        senderName: configuration.user.name,
        content: attachment.fileName,
        type: attachment.type == .image ? .image : .file,
        createdAt: Date(),
        attachment: attachment
      )
      append(optimisticMessage, replacingLocalEcho: false)
      try await client.sendAttachment(attachment, text: attachment.fileName, roomID: roomID)
    } catch {
      errorMessage = error.localizedDescription
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

  func messages(for roomID: String) -> [InstaChatMessage] {
    messagesByRoom[roomID] ?? []
  }

  private func applyRealtimeEvent(_ event: InstaChatRealtimeEvent) {
    switch event {
    case let .message(message):
      upsert(message)
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
        messages[localEchoIndex] = fetchedMessage
      } else {
        messages.append(fetchedMessage)
      }
    }

    messages.sort { $0.createdAt < $1.createdAt }
    messagesByRoom[roomID] = messages
  }

  private func upsert(_ message: InstaChatMessage) {
    var messages = messagesByRoom[message.roomID] ?? []

    if let existingIndex = messages.firstIndex(where: { $0.id == message.id }) {
      messages[existingIndex] = message
    } else if let localEchoIndex = localEchoIndex(for: message, in: messages) {
      messages[localEchoIndex] = message
    } else {
      messages.append(message)
    }

    messages.sort { $0.createdAt < $1.createdAt }
    messagesByRoom[message.roomID] = messages
  }

  private func append(_ message: InstaChatMessage, replacingLocalEcho: Bool) {
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
  }

  private func localEchoIndex(for message: InstaChatMessage, in messages: [InstaChatMessage]) -> Int? {
    guard message.senderID == configuration.user.id else {
      return nil
    }

    return messages.lastIndex { candidate in
      guard candidate.id.hasPrefix("local-"), candidate.senderID == configuration.user.id else {
        return false
      }
      guard abs(candidate.createdAt.timeIntervalSince(message.createdAt)) < 300 else {
        return false
      }
      return candidate.localEchoKey == message.localEchoKey
    }
  }
}

extension InstaChatMessage {
  var localEchoKey: String {
    let attachmentKey = attachment?.id ?? ""
    let locationKey = location.map { "\($0.latitude):\($0.longitude):\($0.name ?? "")" } ?? ""
    return [roomID, senderID, type.rawValue, content, attachmentKey, locationKey].joined(separator: "|")
  }
}
