import XCTest
@testable import InstaChatIOS

final class InstaChatContractTests: XCTestCase {
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
    XCTAssertEqual(MimeTypeResolver.attachmentType(for: "application/pdf"), .file)
  }
}
