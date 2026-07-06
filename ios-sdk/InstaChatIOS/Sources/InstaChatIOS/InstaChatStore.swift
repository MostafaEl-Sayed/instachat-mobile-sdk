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
      messagesByRoom[roomID] = page.messages
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
      append(message, replacingLocalEcho: true)
    case let .typing(roomID, _, isTyping):
      if isTyping {
        typingRoomIDs.insert(roomID)
      } else {
        typingRoomIDs.remove(roomID)
      }
    }
  }

  private func append(_ message: InstaChatMessage, replacingLocalEcho: Bool) {
    var messages = messagesByRoom[message.roomID] ?? []
    if messages.contains(where: { $0.id == message.id }) {
      return
    }

    if replacingLocalEcho, message.senderID == configuration.user.id, let index = messages.lastIndex(where: { $0.id.hasPrefix("local-") && $0.content == message.content }) {
      messages[index] = message
    } else {
      messages.append(message)
    }

    messages.sort { $0.createdAt < $1.createdAt }
    messagesByRoom[message.roomID] = messages
  }
}
