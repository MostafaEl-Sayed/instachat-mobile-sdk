import Foundation

public struct InstaChatConfiguration: Sendable {
  public var baseURL: URL
  public var token: String
  public var user: InstaChatUser
  public var roomID: String?
  public var historyLimit: Int
  public var title: String

  public init(
    baseURL: URL,
    token: String,
    user: InstaChatUser,
    roomID: String? = nil,
    historyLimit: Int = 25,
    title: String = "Messages"
  ) {
    self.baseURL = baseURL
    self.token = token
    self.user = user
    self.roomID = roomID
    self.historyLimit = historyLimit
    self.title = title
  }
}

public struct InstaChatUser: Identifiable, Hashable, Sendable {
  public var id: String
  public var name: String
  public var avatarURL: URL?

  public init(id: String, name: String, avatarURL: URL? = nil) {
    self.id = id
    self.name = name
    self.avatarURL = avatarURL
  }
}

public struct InstaChatRoom: Identifiable, Hashable, Sendable {
  public var id: String
  public var title: String
  public var subtitle: String?
  public var avatarURL: URL?
  public var updatedAt: Date?
  public var unreadCount: Int

  public init(
    id: String,
    title: String,
    subtitle: String? = nil,
    avatarURL: URL? = nil,
    updatedAt: Date? = nil,
    unreadCount: Int = 0
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.avatarURL = avatarURL
    self.updatedAt = updatedAt
    self.unreadCount = unreadCount
  }
}

public struct InstaChatMessage: Identifiable, Hashable, Sendable {
  public var id: String
  public var roomID: String
  public var senderID: String
  public var senderName: String?
  public var content: String
  public var type: InstaChatMessageType
  public var createdAt: Date
  public var attachment: InstaChatAttachment?
  public var location: InstaChatLocation?

  public init(
    id: String,
    roomID: String,
    senderID: String,
    senderName: String? = nil,
    content: String,
    type: InstaChatMessageType,
    createdAt: Date,
    attachment: InstaChatAttachment? = nil,
    location: InstaChatLocation? = nil
  ) {
    self.id = id
    self.roomID = roomID
    self.senderID = senderID
    self.senderName = senderName
    self.content = content
    self.type = type
    self.createdAt = createdAt
    self.attachment = attachment
    self.location = location
  }
}

public enum InstaChatMessageType: String, Codable, Hashable, Sendable {
  case text
  case image
  case file
  case location
}

public struct InstaChatAttachment: Identifiable, Hashable, Sendable {
  public var id: String
  public var fileName: String
  public var contentType: String
  public var type: InstaChatAttachmentType
  public var fileSize: Int?
  public var url: URL

  public init(
    id: String,
    fileName: String,
    contentType: String,
    type: InstaChatAttachmentType,
    fileSize: Int? = nil,
    url: URL
  ) {
    self.id = id
    self.fileName = fileName
    self.contentType = contentType
    self.type = type
    self.fileSize = fileSize
    self.url = url
  }
}

public enum InstaChatAttachmentType: String, Codable, Hashable, Sendable {
  case image
  case video
  case audio
  case file
}

public struct InstaChatLocation: Codable, Hashable, Sendable {
  public var latitude: Double
  public var longitude: Double
  public var name: String?

  public init(latitude: Double, longitude: Double, name: String? = nil) {
    self.latitude = latitude
    self.longitude = longitude
    self.name = name
  }
}

public struct InstaChatMessagesPage: Sendable {
  public var messages: [InstaChatMessage]
  public var nextCursor: String?
  public var hasMore: Bool
}
