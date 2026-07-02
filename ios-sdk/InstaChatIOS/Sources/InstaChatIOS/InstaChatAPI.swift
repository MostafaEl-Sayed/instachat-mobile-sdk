import Foundation

public enum InstaChatError: LocalizedError, Sendable {
  case invalidResponse
  case backendStatus(Int, String)
  case missingRoom
  case websocketClosed
  case invalidLocationPayload

  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "The backend returned an invalid response."
    case let .backendStatus(status, body):
      return "The backend returned \(status): \(body)"
    case .missingRoom:
      return "No chat room is available for this user."
    case .websocketClosed:
      return "The realtime connection is closed."
    case .invalidLocationPayload:
      return "The location message could not be encoded."
    }
  }
}

public final class InstaChatClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
  private let configuration: InstaChatConfiguration
  private let session: URLSession
  private let decoder: JSONDecoder
  private let encoder = JSONEncoder()
  private var webSocketTask: URLSessionWebSocketTask?
  private var messageContinuation: AsyncStream<InstaChatRealtimeEvent>.Continuation?

  public init(configuration: InstaChatConfiguration, session: URLSession = .shared) {
    self.configuration = configuration
    self.session = session
    self.decoder = JSONDecoder()
    self.decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
  }

  public func getRooms() async throws -> [InstaChatRoom] {
    let rooms: [BackendRoom] = try await request(path: "/api/v1/me/rooms")
    return rooms.map { $0.toDomain(currentUserID: configuration.user.id) }
  }

  public func getMessages(roomID: String, limit: Int? = nil, cursor: String? = nil) async throws -> InstaChatMessagesPage {
    var components = URLComponents(url: configuration.baseURL.appendingInstaChatPath("api/v1/rooms/\(roomID)/messages"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "limit", value: "\(limit ?? configuration.historyLimit)")
    ]
    if let cursor {
      components?.queryItems?.append(URLQueryItem(name: "cursor", value: cursor))
    }

    guard let url = components?.url else {
      throw InstaChatError.invalidResponse
    }

    let page: BackendMessagesPage = try await request(url: url)
    return InstaChatMessagesPage(
      messages: page.data.map { $0.toDomain(currentUserID: configuration.user.id) }.sorted { $0.createdAt < $1.createdAt },
      nextCursor: page.nextCursor,
      hasMore: page.nextCursor != nil
    )
  }

  public func uploadAttachment(fileURL: URL, roomID: String, contentType: String? = nil) async throws -> InstaChatAttachment {
    var uploadRequest = URLRequest(url: configuration.baseURL.appendingInstaChatPath("api/v1/rooms/\(roomID)/attachments"))
    let boundary = "Boundary-\(UUID().uuidString)"
    uploadRequest.httpMethod = "POST"
    uploadRequest.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
    uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let fileName = fileURL.lastPathComponent.isEmpty ? "upload" : fileURL.lastPathComponent
    let mimeType = contentType ?? MimeTypeResolver.mimeType(for: fileURL)
    uploadRequest.httpBody = try MultipartFormDataBuilder(boundary: boundary)
      .appendFile(fieldName: "file", fileName: fileName, mimeType: mimeType, fileURL: fileURL)
      .finalize()

    let attachment: BackendAttachment = try await request(uploadRequest)
    return attachment.toDomain()
  }

  public func sendText(_ text: String, roomID: String) async throws {
    try await sendMessage(content: text, type: .text, roomID: roomID, attachmentIDs: [])
  }

  public func sendLocation(_ location: InstaChatLocation, roomID: String) async throws {
    guard let content = String(data: try encoder.encode(location), encoding: .utf8) else {
      throw InstaChatError.invalidLocationPayload
    }
    try await sendMessage(content: content, type: .location, roomID: roomID, attachmentIDs: [])
  }

  public func sendAttachment(_ attachment: InstaChatAttachment, text: String = "", roomID: String) async throws {
    let messageType: InstaChatMessageType = attachment.type == .image ? .image : .file
    try await sendMessage(content: text, type: messageType, roomID: roomID, attachmentIDs: [attachment.id])
  }

  public func sendTyping(roomID: String, isTyping: Bool) async throws {
    let envelope = RealtimeOutgoingEnvelope(
      type: isTyping ? "typing.start" : "typing.stop",
      payload: RealtimeOutgoingPayload(roomID: roomID, content: nil, type: nil, attachmentIDs: nil)
    )
    try await sendWebSocket(envelope)
  }

  public func realtimeEvents() -> AsyncStream<InstaChatRealtimeEvent> {
    AsyncStream { continuation in
      messageContinuation = continuation
      connectWebSocketIfNeeded()
      receiveNextWebSocketMessage()
      continuation.onTermination = { [weak self] _ in
        self?.disconnect()
      }
    }
  }

  public func disconnect() {
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
    messageContinuation?.finish()
    messageContinuation = nil
  }

  private func sendMessage(content: String, type: InstaChatMessageType, roomID: String, attachmentIDs: [String]) async throws {
    let envelope = RealtimeOutgoingEnvelope(
      type: "message.send",
      payload: RealtimeOutgoingPayload(roomID: roomID, content: content, type: type.rawValue, attachmentIDs: attachmentIDs)
    )
    try await sendWebSocket(envelope)
  }

  private func sendWebSocket(_ envelope: RealtimeOutgoingEnvelope) async throws {
    connectWebSocketIfNeeded()
    guard let webSocketTask else {
      throw InstaChatError.websocketClosed
    }
    let data = try encoder.encode(envelope)
    guard let text = String(data: data, encoding: .utf8) else {
      throw InstaChatError.invalidResponse
    }
    try await webSocketTask.send(.string(text))
  }

  private func connectWebSocketIfNeeded() {
    guard webSocketTask == nil else {
      return
    }

    var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
    components?.scheme = configuration.baseURL.scheme == "http" ? "ws" : "wss"
    components?.path = "/ws"
    components?.queryItems = [URLQueryItem(name: "token", value: configuration.token)]

    guard let url = components?.url else {
      return
    }

    let task = session.webSocketTask(with: url)
    webSocketTask = task
    task.resume()
  }

  private func receiveNextWebSocketMessage() {
    webSocketTask?.receive { [weak self] result in
      guard let self else {
        return
      }

      switch result {
      case let .success(message):
        self.handleWebSocketMessage(message)
        self.receiveNextWebSocketMessage()
      case .failure:
        self.disconnect()
      }
    }
  }

  private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
    let text: String?
    switch message {
    case let .string(value):
      text = value
    case let .data(data):
      text = String(data: data, encoding: .utf8)
    @unknown default:
      text = nil
    }

    text?
      .split(whereSeparator: \.isNewline)
      .compactMap { $0.data(using: .utf8) }
      .compactMap { try? decoder.decode(RealtimeIncomingEnvelope.self, from: $0) }
      .compactMap { $0.toDomain(currentUserID: configuration.user.id) }
      .forEach { messageContinuation?.yield($0) }
  }

  private func request<T: Decodable>(path: String) async throws -> T {
    try await request(url: configuration.baseURL.appendingInstaChatPath(path))
  }

  private func request<T: Decodable>(url: URL) async throws -> T {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
    return try await self.request(request)
  }

  private func request<T: Decodable>(_ request: URLRequest) async throws -> T {
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw InstaChatError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw InstaChatError.backendStatus(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
    }
    return try decoder.decode(T.self, from: data)
  }
}

public enum InstaChatRealtimeEvent: Sendable {
  case message(InstaChatMessage)
  case typing(roomID: String, userID: String?, isTyping: Bool)
}

struct RealtimeOutgoingEnvelope: Encodable {
  var type: String
  var payload: RealtimeOutgoingPayload
}

struct RealtimeOutgoingPayload: Encodable {
  var roomID: String
  var content: String?
  var type: String?
  var attachmentIDs: [String]?

  enum CodingKeys: String, CodingKey {
    case roomID = "room_id"
    case content
    case type
    case attachmentIDs = "attachment_ids"
  }
}

struct RealtimeIncomingEnvelope: Decodable {
  var type: String
  var payload: BackendMessageOrTypingPayload?

  func toDomain(currentUserID: String) -> InstaChatRealtimeEvent? {
    guard let payload else {
      return nil
    }

    switch type {
    case "message.new":
      return payload.message.map { .message($0.toDomain(currentUserID: currentUserID)) }
    case "typing":
      return .typing(roomID: payload.roomID ?? "", userID: payload.userID, isTyping: payload.isTyping ?? false)
    default:
      return nil
    }
  }
}

struct BackendMessageOrTypingPayload: Decodable {
  var id: String?
  var roomID: String?
  var senderID: String?
  var content: String?
  var type: InstaChatMessageType?
  var createdAt: Date?
  var attachments: [BackendAttachment]?
  var userID: String?
  var isTyping: Bool?

  enum CodingKeys: String, CodingKey {
    case id
    case roomID = "room_id"
    case senderID = "sender_id"
    case content
    case type
    case createdAt = "created_at"
    case attachments
    case userID = "user_id"
    case isTyping = "is_typing"
  }

  var message: BackendMessage? {
    guard let id, let roomID, let senderID, let content, let type, let createdAt else {
      return nil
    }
    return BackendMessage(
      id: id,
      roomID: roomID,
      senderID: senderID,
      content: content,
      type: type,
      createdAt: createdAt,
      attachments: attachments
    )
  }
}

struct BackendRoom: Decodable {
  var id: String
  var type: String?
  var createdAt: Date?
  var members: [BackendRoomMember]?

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case createdAt = "created_at"
    case members
  }

  func toDomain(currentUserID: String) -> InstaChatRoom {
    let otherMember = members?.first { ($0.externalUserID ?? $0.id) != currentUserID } ?? members?.first
    return InstaChatRoom(
      id: id,
      title: otherMember?.displayName ?? "Chat",
      subtitle: otherMember?.isOnline == true ? "Online" : nil,
      avatarURL: otherMember?.avatarURL,
      updatedAt: createdAt
    )
  }
}

struct BackendRoomMember: Decodable {
  var id: String
  var externalUserID: String?
  var displayName: String
  var avatarURL: URL?
  var isOnline: Bool?

  enum CodingKeys: String, CodingKey {
    case id
    case externalUserID = "ext_user_id"
    case displayName = "display_name"
    case avatarURL = "avatar_url"
    case isOnline = "is_online"
  }
}

struct BackendMessagesPage: Decodable {
  var data: [BackendMessage]
  var nextCursor: String?

  enum CodingKeys: String, CodingKey {
    case data
    case nextCursor = "next_cursor"
  }
}

struct BackendMessage: Decodable {
  var id: String
  var roomID: String
  var senderID: String
  var content: String
  var type: InstaChatMessageType
  var createdAt: Date
  var attachments: [BackendAttachment]?

  enum CodingKeys: String, CodingKey {
    case id
    case roomID = "room_id"
    case senderID = "sender_id"
    case content
    case type
    case createdAt = "created_at"
    case attachments
  }

  func toDomain(currentUserID _: String) -> InstaChatMessage {
    let attachment = attachments?.first?.toDomain()
    let location = type == .location ? try? JSONDecoder().decode(InstaChatLocation.self, from: Data(content.utf8)) : nil
    return InstaChatMessage(
      id: id,
      roomID: roomID,
      senderID: senderID,
      content: content,
      type: type,
      createdAt: createdAt,
      attachment: attachment,
      location: location
    )
  }
}

struct BackendAttachment: Decodable {
  var id: String
  var fileName: String
  var contentType: String
  var type: InstaChatAttachmentType?
  var fileSize: Int?
  var url: URL

  enum CodingKeys: String, CodingKey {
    case id
    case fileName = "file_name"
    case contentType = "content_type"
    case type
    case fileSize = "file_size"
    case url
  }

  func toDomain() -> InstaChatAttachment {
    InstaChatAttachment(
      id: id,
      fileName: fileName,
      contentType: contentType,
      type: type ?? MimeTypeResolver.attachmentType(for: contentType),
      fileSize: fileSize,
      url: url
    )
  }
}

struct MultipartFormDataBuilder {
  private let boundary: String
  private var data = Data()

  init(boundary: String) {
    self.boundary = boundary
  }

  func appendFile(fieldName: String, fileName: String, mimeType: String, fileURL: URL) throws -> MultipartFormDataBuilder {
    var copy = self
    copy.data.append("--\(boundary)\r\n".data(using: .utf8)!)
    copy.data.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
    copy.data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
    copy.data.append(try Data(contentsOf: fileURL))
    copy.data.append("\r\n".data(using: .utf8)!)
    return copy
  }

  func finalize() -> Data {
    var copy = data
    copy.append("--\(boundary)--\r\n".data(using: .utf8)!)
    return copy
  }
}

enum MimeTypeResolver {
  static func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "gif":
      return "image/gif"
    case "mp4":
      return "video/mp4"
    case "mov":
      return "video/quicktime"
    case "m4a":
      return "audio/mp4"
    case "wav":
      return "audio/wav"
    default:
      return "application/octet-stream"
    }
  }

  static func attachmentType(for contentType: String) -> InstaChatAttachmentType {
    if contentType.hasPrefix("image/") {
      return .image
    }
    if contentType.hasPrefix("video/") {
      return .video
    }
    if contentType.hasPrefix("audio/") {
      return .audio
    }
    return .file
  }
}

extension JSONDecoder.DateDecodingStrategy {
  static let iso8601WithFractionalSeconds = custom { decoder in
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: value) ?? ISO8601DateFormatter.standard.date(from: value) {
      return date
    }
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
  }
}

extension ISO8601DateFormatter {
  static let standard: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  static let withFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

private extension URL {
  func appendingInstaChatPath(_ path: String) -> URL {
    let trimmedBase = absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return URL(string: "\(trimmedBase)/\(trimmedPath)") ?? appendingPathComponent(trimmedPath)
  }
}
