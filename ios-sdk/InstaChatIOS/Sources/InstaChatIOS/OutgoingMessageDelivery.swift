import Foundation

enum OutgoingMessageDeliveryState: Equatable, Sendable {
  case sending
  case failed(InstaChatSendFailure)
}

struct InstaChatSendFailure: Codable, Hashable, Sendable {
  var message: String

  static func userFacing(for error: Error, attachmentType: InstaChatAttachmentType? = nil, language: InstaChatLanguage = .devicePreferred) -> InstaChatSendFailure {
    let strings = InstaChatLocalizer(language: language)
    let item = itemName(for: attachmentType, strings: strings)

    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
        return InstaChatSendFailure(message: strings.format("No internet connection. Reconnect, then retry your %@.", item))
      case .timedOut:
        return InstaChatSendFailure(message: strings.format("Sending your %@ took too long. Check your connection and retry.", item))
      default:
        break
      }
    }

    if let chatError = error as? InstaChatError {
      switch chatError {
      case .websocketClosed:
        return InstaChatSendFailure(message: strings.format("Chat is reconnecting. Retry your %@ in a moment.", item))
      case let .backendStatus(status, _):
        switch status {
        case 401, 403:
          return InstaChatSendFailure(message: strings.text("Your chat session has expired. Reopen chat, then retry."))
        case 413:
          return InstaChatSendFailure(message: strings.format("This %@ is too large to send. Choose a smaller file.", item))
        case 429:
          return InstaChatSendFailure(message: strings.format("Too many requests. Wait a moment, then retry your %@.", item))
        case 500...599:
          return InstaChatSendFailure(message: strings.format("The chat service is temporarily unavailable. Retry your %@ shortly.", item))
        default:
          break
        }
      case .invalidResponse:
        return InstaChatSendFailure(message: strings.format("The chat service returned an unexpected response. Retry your %@.", item))
      case .missingRoom:
        return InstaChatSendFailure(message: strings.text("This conversation is no longer available."))
      case .invalidLocationPayload:
        return InstaChatSendFailure(message: strings.text("Your location could not be prepared. Please share it again."))
      }
    }

    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileNoSuchFileError {
      return InstaChatSendFailure(message: strings.format("The original %@ is no longer available. Choose it again.", item))
    }

    return InstaChatSendFailure(message: strings.format("We couldn't send your %@. Check your connection and retry.", item))
  }

  static func interrupted(attachmentType: InstaChatAttachmentType? = nil, language: InstaChatLanguage = .devicePreferred) -> InstaChatSendFailure {
    let strings = InstaChatLocalizer(language: language)
    return InstaChatSendFailure(message: strings.format("Sending was interrupted. Tap Retry to send your %@.", itemName(for: attachmentType, strings: strings)))
  }

  static func actionMessage(for error: Error, language: InstaChatLanguage = .devicePreferred) -> String {
    userFacing(for: error, language: language).message
  }

  private static func itemName(for attachmentType: InstaChatAttachmentType?, strings: InstaChatLocalizer) -> String {
    switch attachmentType {
    case .image:
      return strings.text("photo")
    case .video:
      return strings.text("video")
    case .audio:
      return strings.text("voice note")
    case .file:
      return strings.text("file")
    case .none:
      return strings.text("message")
    }
  }
}

enum PendingOutgoingPayload: Codable, Hashable, Sendable {
  case text(String)
  case location(InstaChatLocation)
  case attachment(localFileURL: URL, contentType: String?, uploadedAttachment: InstaChatAttachment?)

  var attachmentType: InstaChatAttachmentType? {
    switch self {
    case .text, .location:
      return nil
    case let .attachment(localFileURL, contentType, uploadedAttachment):
      return uploadedAttachment?.type ?? MimeTypeResolver.attachmentType(
        for: contentType ?? MimeTypeResolver.mimeType(for: localFileURL)
      )
    }
  }
}

struct PendingOutgoingMessage: Codable, Hashable, Sendable {
  var message: InstaChatMessage
  var payload: PendingOutgoingPayload
  var failure: InstaChatSendFailure?
}

final class PendingOutgoingMessageStore: @unchecked Sendable {
  private let fileURL: URL

  convenience init(configuration: InstaChatConfiguration) {
    let identity = "\(configuration.baseURL.absoluteString)|\(configuration.user.id)"
    let fileName = Data(identity.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
    let root = (try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )) ?? FileManager.default.temporaryDirectory
    self.init(fileURL: root
      .appendingPathComponent("InstaChat", isDirectory: true)
      .appendingPathComponent("Pending", isDirectory: true)
      .appendingPathComponent(fileName)
      .appendingPathExtension("json"))
  }

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  func load() -> [PendingOutgoingMessage] {
    guard let data = try? Data(contentsOf: fileURL) else {
      return []
    }
    return (try? JSONDecoder().decode([PendingOutgoingMessage].self, from: data)) ?? []
  }

  func save(_ messages: [PendingOutgoingMessage]) {
    do {
      if messages.isEmpty {
        try? FileManager.default.removeItem(at: fileURL)
        return
      }

      let directory = fileURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var mutableDirectory = directory
      try? mutableDirectory.setResourceValues(values)
      let data = try JSONEncoder().encode(messages)
      try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    } catch {
      // A send must never be blocked because local recovery metadata could not be saved.
    }
  }

  func preserveFile(at sourceURL: URL, messageID: String) async throws -> URL {
    let destinationDirectory = fileURL
      .deletingPathExtension()
      .appendingPathExtension("files")
    let fileExtension = sourceURL.pathExtension
    let destinationURL = destinationDirectory
      .appendingPathComponent(messageID)
      .appendingPathExtension(fileExtension)

    if sourceURL == destinationURL {
      return sourceURL
    }

    return try await Task.detached(priority: .utility) {
      try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
      }
      try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
      return destinationURL
    }.value
  }

  func removePreservedFile(for pending: PendingOutgoingMessage) {
    guard case let .attachment(localFileURL, _, _) = pending.payload else {
      return
    }
    try? FileManager.default.removeItem(at: localFileURL)
  }
}
