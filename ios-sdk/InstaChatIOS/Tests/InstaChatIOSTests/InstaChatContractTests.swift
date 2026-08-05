import XCTest
@testable import InstaChatIOS

final class InstaChatContractTests: XCTestCase {
  func testConfigurationCanOpenSpecificRoomFromInitializedSDK() {
    let sdk = InstaChat.initialize(
      baseURL: URL(string: "https://instachat.instakit.pro")!,
      token: "token",
      user: InstaChatUser(id: "user-1", name: "Mostafa")
    )

    let roomConfiguration = sdk.configuration.openingRoom(id: "room-1", title: "Support")

    XCTAssertEqual(sdk.configuration.roomID, nil)
    XCTAssertEqual(roomConfiguration.roomID, "room-1")
    XCTAssertEqual(roomConfiguration.initialRoom?.id, "room-1")
    XCTAssertEqual(roomConfiguration.initialRoom?.title, "Support")
  }

  func testSDKConfigurationInitializerPreservesInitialRoom() {
    let configuration = InstaChatConfiguration(
      baseURL: URL(string: "https://instachat.instakit.pro")!,
      token: "token",
      user: InstaChatUser(id: "user-1", name: "Mostafa"),
      roomID: "room-1",
      roomTitle: "Support"
    )

    let sdk = InstaChatSDK(configuration: configuration)

    XCTAssertEqual(sdk.configuration.roomID, "room-1")
    XCTAssertEqual(sdk.configuration.initialRoom?.title, "Support")
  }

  func testRoomListDecodesLiveBackendShapeWithEmptyAvatarURL() throws {
    let json = """
    {
      "id": "room-1",
      "app_id": "app-1",
      "type": "direct",
      "created_at": "2026-06-28T21:36:49Z",
      "members": [
        {
          "id": "member-1",
          "ext_user_id": "user-2",
          "display_name": "User-2: Hisham",
          "avatar_url": "https://i.pravatar.cc/150?img=7",
          "profile_url": "https://example.com/providers/user-2",
          "is_online": true
        },
        {
          "id": "member-2",
          "ext_user_id": "admin_1",
          "display_name": "admin",
          "avatar_url": "",
          "is_online": false
        }
      ],
      "last_message": {
        "id": "message-1",
        "sender_id": "user-1",
        "content": "SDK validation ping",
        "type": "text",
        "created_at": "2026-07-02T22:46:06Z"
      },
      "unread_count": 3
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
    let backendRoom = try decoder.decode(BackendRoom.self, from: json)
    let room = backendRoom.toDomain(currentUserID: "user-1")

    XCTAssertEqual(room.title, "User-2: Hisham")
    XCTAssertEqual(room.subtitle, "SDK validation ping")
    XCTAssertEqual(room.unreadCount, 3)
    XCTAssertNotNil(room.avatarURL)
    XCTAssertEqual(room.providerID, "member-1")
    XCTAssertEqual(room.providerExternalUserID, "user-2")
    XCTAssertEqual(room.providerProfileURL?.absoluteString, "https://example.com/providers/user-2")
  }

  func testLocationMessageDecodesFromBackendJSONContent() throws {
    let json = """
    {
      "id": "m-location",
      "room_id": "room-1",
      "sender_id": "user-1",
      "content": "{\\"latitude\\":37.7749,\\"longitude\\":-122.4194,\\"name\\":\\"Office\\"}",
      "type": "location",
      "created_at": "2026-06-29T10:02:00Z"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
    let backendMessage = try decoder.decode(BackendMessage.self, from: json)
    let message = backendMessage.toDomain(currentUserID: "user-1")

    XCTAssertEqual(message.type, .location)
    XCTAssertEqual(message.location?.latitude, 37.7749)
    XCTAssertEqual(message.location?.longitude, -122.4194)
    XCTAssertEqual(message.location?.name, "Office")
  }

  func testBackendSenderIDMapsToCurrentExternalUserID() throws {
    let json = """
    {
      "id": "m-current-user",
      "room_id": "room-1",
      "sender_id": "a98ad361-a041-4d4e-907c-d6fb1372b3be",
      "content": "Hello",
      "type": "text",
      "created_at": "2026-07-06T14:03:00Z"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
    let backendMessage = try decoder.decode(BackendMessage.self, from: json)
    let message = backendMessage.toDomain(
      currentUserID: "user-1",
      currentBackendUserID: "a98ad361-a041-4d4e-907c-d6fb1372b3be"
    )

    XCTAssertEqual(message.senderID, "user-1")
  }

  func testTokenIdentityMapsBackendEchoToConfiguredUserID() throws {
    let token = Self.jwt(payload: [
      "sub": "backend-user-1",
      "ext_user_id": "external-user-1"
    ])
    let identity = InstaChatTokenIdentity(token: token)
    let json = """
    {
      "id": "m-current-user",
      "room_id": "room-1",
      "sender_id": "backend-user-1",
      "content": "Hello",
      "type": "text",
      "created_at": "2026-07-06T14:03:00Z"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
    let backendMessage = try decoder.decode(BackendMessage.self, from: json)
    let message = backendMessage.toDomain(
      currentUserID: "configured-user-id",
      currentBackendUserID: identity.subject
    )

    XCTAssertEqual(identity.externalUserID, "external-user-1")
    XCTAssertEqual(message.senderID, "configured-user-id")
  }

  func testAutomaticMessageWithoutSenderIDStillRendersAsProviderMessage() throws {
    let json = """
    {
      "id": "m-automatic",
      "room_id": "room-1",
      "content": "Thanks for reaching out. We will reply soon.",
      "type": "automatic",
      "created_at": "2026-07-06T14:03:00Z",
      "sender": {
        "display_name": "Provider"
      }
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
    let backendMessage = try decoder.decode(BackendMessage.self, from: json)
    let message = backendMessage.toDomain(currentUserID: "user-1", currentBackendUserID: "backend-user-1")

    XCTAssertEqual(message.type, .text)
    XCTAssertEqual(message.senderID, "provider")
    XCTAssertEqual(message.senderName, "Provider")
    XCTAssertEqual(message.content, "Thanks for reaching out. We will reply soon.")
  }

  func testOutgoingLocationPayloadMatchesBackendContract() throws {
    let location = InstaChatLocation(latitude: 30.0444, longitude: 31.2357, name: "Cairo")
    let content = String(data: try JSONEncoder().encode(location), encoding: .utf8)
    let decoded = try XCTUnwrap(content?.data(using: .utf8)).withUnsafeBytes { buffer in
      try JSONDecoder().decode(InstaChatLocation.self, from: Data(buffer))
    }

    XCTAssertEqual(decoded.latitude, 30.0444)
    XCTAssertEqual(decoded.longitude, 31.2357)
    XCTAssertEqual(decoded.name, "Cairo")
  }

  func testAttachmentTypeFallsBackFromMimeType() {
    XCTAssertEqual(MimeTypeResolver.attachmentType(for: "image/png"), .image)
    XCTAssertEqual(MimeTypeResolver.attachmentType(for: "video/mp4"), .video)
    XCTAssertEqual(MimeTypeResolver.attachmentType(for: "audio/mp4"), .audio)
    XCTAssertEqual(MimeTypeResolver.attachmentType(for: "audio/m4a"), .audio)
    XCTAssertEqual(MimeTypeResolver.attachmentType(for: "application/pdf"), .file)
  }

  func testAudioAttachmentDecodesFromBackendFileMessage() throws {
    let json = """
    {
      "id": "m-audio",
      "room_id": "room-1",
      "sender_id": "user-2",
      "content": "voice-note.m4a",
      "type": "file",
      "created_at": "2026-07-06T14:03:00Z",
      "attachments": [
        {
          "id": "att-audio",
          "file_name": "voice-note.m4a",
          "content_type": "audio/mp4",
          "file_size": 24576,
          "url": "https://instachat.instakit.pro/uploads/voice-note.m4a"
        }
      ]
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
    let backendMessage = try decoder.decode(BackendMessage.self, from: json)
    let message = backendMessage.toDomain(currentUserID: "user-1")

    XCTAssertEqual(message.type, .file)
    XCTAssertEqual(message.attachment?.type, .audio)
    XCTAssertEqual(message.attachment?.contentType, "audio/mp4")
    XCTAssertEqual(message.attachment?.fileName, "voice-note.m4a")
  }

  func testLocalEchoKeyMatchesBackendEchoForSameTextMessage() {
    let localMessage = InstaChatMessage(
      id: "local-1",
      roomID: "room-1",
      senderID: "user-1",
      content: "Hello",
      type: .text,
      createdAt: Date()
    )
    let backendEcho = InstaChatMessage(
      id: "server-1",
      roomID: "room-1",
      senderID: "user-1",
      content: "Hello",
      type: .text,
      createdAt: Date()
    )

    XCTAssertEqual(localMessage.localEchoKey, backendEcho.localEchoKey)
  }

  @MainActor
  func testOptimisticSendUpdatesRoomPreviewAndMovesRoomToTop() {
    let store = InstaChatStore(configuration: Self.testConfiguration())
    store.append(Self.message(id: "old", roomID: "room-1", content: "Old", createdAt: Self.date(1)), replacingLocalEcho: false)
    store.append(Self.message(id: "older-other", roomID: "room-2", content: "Older", createdAt: Self.date(2)), replacingLocalEcho: false)

    let sentMessage = Self.message(
      id: "local-new",
      roomID: "room-1",
      senderID: "user-1",
      content: "Latest sent text",
      createdAt: Self.date(3)
    )
    store.append(sentMessage, replacingLocalEcho: false)

    XCTAssertEqual(store.rooms.map(\.id), ["room-1", "room-2"])
    XCTAssertEqual(store.room(id: "room-1")?.subtitle, "Latest sent text")
    XCTAssertEqual(store.room(id: "room-1")?.updatedAt, Self.date(3))
    XCTAssertEqual(store.room(id: "room-1")?.unreadCount, 0)
  }

  @MainActor
  func testIncomingRealtimeMessageUpdatesPreviewOrderAndUnreadWhenRoomIsNotActive() {
    let store = InstaChatStore(configuration: Self.testConfiguration())
    store.append(Self.message(id: "room-1-old", roomID: "room-1", content: "Room 1", createdAt: Self.date(1)), replacingLocalEcho: false)
    store.append(Self.message(id: "room-2-old", roomID: "room-2", content: "Room 2", createdAt: Self.date(2)), replacingLocalEcho: false)

    let incoming = Self.message(
      id: "incoming",
      roomID: "room-1",
      senderID: "provider-1",
      content: "Provider reply",
      createdAt: Self.date(4)
    )
    store.applyRealtimeEvent(.message(incoming))

    XCTAssertEqual(store.rooms.map(\.id), ["room-1", "room-2"])
    XCTAssertEqual(store.room(id: "room-1")?.subtitle, "Provider reply")
    XCTAssertEqual(store.room(id: "room-1")?.updatedAt, Self.date(4))
    XCTAssertEqual(store.room(id: "room-1")?.unreadCount, 1)
  }

  @MainActor
  func testIncomingRealtimeMessageDoesNotIncrementUnreadForActiveRoom() {
    let store = InstaChatStore(configuration: Self.testConfiguration())
    store.setActiveRoom("room-1")

    let incoming = Self.message(
      id: "incoming-active",
      roomID: "room-1",
      senderID: "provider-1",
      content: "Visible reply",
      createdAt: Self.date(5)
    )
    store.applyRealtimeEvent(.message(incoming))

    XCTAssertEqual(store.room(id: "room-1")?.subtitle, "Visible reply")
    XCTAssertEqual(store.room(id: "room-1")?.unreadCount, 0)
  }

  @MainActor
  func testRoomPreviewCoversLocationImageVideoVoiceAndFileMessages() {
    let store = InstaChatStore(configuration: Self.testConfiguration())
    let samples: [(InstaChatMessage, String)] = [
      (
        Self.message(
          id: "location",
          roomID: "room-location",
          content: #"{"latitude":30,"longitude":31,"name":"Cairo"}"#,
          type: .location,
          createdAt: Self.date(1),
          location: InstaChatLocation(latitude: 30, longitude: 31, name: "Cairo")
        ),
        "Cairo"
      ),
      (
        Self.message(
          id: "image",
          roomID: "room-image",
          content: "",
          type: .image,
          createdAt: Self.date(2),
          attachment: Self.attachment(type: .image, fileName: "photo.png", contentType: "image/png")
        ),
        "Photo"
      ),
      (
        Self.message(
          id: "video",
          roomID: "room-video",
          content: "",
          type: .file,
          createdAt: Self.date(3),
          attachment: Self.attachment(type: .video, fileName: "clip.mp4", contentType: "video/mp4")
        ),
        "Video"
      ),
      (
        Self.message(
          id: "voice",
          roomID: "room-voice",
          content: "",
          type: .file,
          createdAt: Self.date(4),
          attachment: Self.attachment(type: .audio, fileName: "voice.m4a", contentType: "audio/mp4")
        ),
        "Voice note"
      ),
      (
        Self.message(
          id: "file",
          roomID: "room-file",
          content: "",
          type: .file,
          createdAt: Self.date(5),
          attachment: Self.attachment(type: .file, fileName: "contract.pdf", contentType: "application/pdf")
        ),
        "File"
      )
    ]

    for (message, expectedPreview) in samples {
      store.append(message, replacingLocalEcho: false)
      XCTAssertEqual(store.room(id: message.roomID)?.subtitle, expectedPreview)
    }
  }

  func testMediaPreflightLimitsMatchSDKContract() {
    XCTAssertEqual(MediaPreflight.maxImageSelectionCount, 5)
    XCTAssertEqual(MediaPreflight.maxVideoDuration, 60)
  }

  func testMessageLinkifierDetectsHTTPAndHTTPSURLsInMultilineText() {
    let text = """
    Please check https://instachat.instakit.pro/provider-details/provider-123
    Backup: http://example.com/path?query=1
    """

    let urls = MessageLinkifier.detectedURLs(in: text).map(\.absoluteString)

    XCTAssertEqual(urls, [
      "https://instachat.instakit.pro/provider-details/provider-123",
      "http://example.com/path?query=1"
    ])
  }

  func testMessageLinkifierIgnoresNonWebSchemes() {
    let urls = MessageLinkifier.detectedURLs(in: "Email mailto:test@example.com and open ftp://example.com")

    XCTAssertTrue(urls.isEmpty)
  }

  func testMessageLinkifierDetectsURLInsideArabicRTLMessage() {
    let text = "مرحبا، افتح هذا الرابط https://instachat.instakit.pro/provider-details/abc123 من فضلك"

    let urls = MessageLinkifier.detectedURLs(in: text).map(\.absoluteString)

    XCTAssertEqual(urls, ["https://instachat.instakit.pro/provider-details/abc123"])
  }

  func testAttributedMessageContainsLinkAttribute() throws {
    let attributed = MessageLinkifier.attributedString(for: "Open https://apps.apple.com/app/id123", isCurrentUser: false)
    let linkedRun = try XCTUnwrap(attributed.runs.first { $0.link != nil })

    XCTAssertEqual(linkedRun.link?.absoluteString, "https://apps.apple.com/app/id123")
    XCTAssertEqual(linkedRun.underlineStyle, .single)
  }

  private static func jwt(payload: [String: String]) -> String {
    let header = #"{"alg":"none","typ":"JWT"}"#
    let payloadData = try! JSONSerialization.data(withJSONObject: payload)
    let payloadString = String(data: payloadData, encoding: .utf8)!
    return [header, payloadString, ""]
      .map { Data($0.utf8).base64URLEncodedString() }
      .joined(separator: ".")
  }

  private static func testConfiguration() -> InstaChatConfiguration {
    InstaChatConfiguration(
      baseURL: URL(string: "https://instachat.instakit.pro")!,
      token: "token",
      user: InstaChatUser(id: "user-1", name: "Mostafa")
    )
  }

  private static func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
  }

  private static func message(
    id: String,
    roomID: String,
    senderID: String = "user-1",
    content: String,
    type: InstaChatMessageType = .text,
    createdAt: Date,
    attachment: InstaChatAttachment? = nil,
    location: InstaChatLocation? = nil
  ) -> InstaChatMessage {
    InstaChatMessage(
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

  private static func attachment(type: InstaChatAttachmentType, fileName: String, contentType: String) -> InstaChatAttachment {
    InstaChatAttachment(
      id: "attachment-\(fileName)",
      fileName: fileName,
      contentType: contentType,
      type: type,
      url: URL(string: "https://instachat.instakit.pro/uploads/\(fileName)")!
    )
  }
}

private extension Data {
  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
