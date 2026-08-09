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

  @MainActor
  func testMixedMediaMessagesKeepChronologicalOrderAndAttachmentIdentity() {
    let store = InstaChatStore(
      configuration: Self.testConfiguration(),
      pendingStore: Self.temporaryPendingStore()
    )
    let image = Self.message(
      id: "image-message",
      roomID: "room-media",
      content: "photo.jpg",
      type: .image,
      createdAt: Self.date(1),
      attachment: Self.attachment(type: .image, fileName: "photo.jpg", contentType: "image/jpeg")
    )
    let voice = Self.message(
      id: "voice-message",
      roomID: "room-media",
      content: "voice.m4a",
      type: .file,
      createdAt: Self.date(2),
      attachment: Self.attachment(type: .audio, fileName: "voice.m4a", contentType: "audio/mp4")
    )
    let video = Self.message(
      id: "video-message",
      roomID: "room-media",
      content: "video.mp4",
      type: .file,
      createdAt: Self.date(3),
      attachment: Self.attachment(type: .video, fileName: "video.mp4", contentType: "video/mp4")
    )

    store.append(video, replacingLocalEcho: false)
    store.append(image, replacingLocalEcho: false)
    store.append(voice, replacingLocalEcho: false)

    let messages = store.messages(for: "room-media")
    XCTAssertEqual(messages.map(\.id), ["image-message", "voice-message", "video-message"])
    XCTAssertEqual(messages.map { $0.attachment?.type }, [.image, .audio, .video])
    XCTAssertEqual(messages.map { $0.attachment?.fileName }, ["photo.jpg", "voice.m4a", "video.mp4"])
  }

  func testMediaPreviewSelectionKeepsExactTappedMessageAndAttachment() {
    let image = Self.attachment(type: .image, fileName: "first.jpg", contentType: "image/jpeg")
    let video = Self.attachment(type: .video, fileName: "second.mp4", contentType: "video/mp4")
    let imageSelection = MediaPreviewSelection(messageID: "message-image", attachment: image)
    let videoSelection = MediaPreviewSelection(messageID: "message-video", attachment: video)

    XCTAssertNotEqual(imageSelection.id, videoSelection.id)
    XCTAssertEqual(imageSelection.messageID, "message-image")
    XCTAssertEqual(imageSelection.attachment.id, image.id)
    XCTAssertEqual(imageSelection.attachment.url, image.url)
    XCTAssertEqual(videoSelection.messageID, "message-video")
    XCTAssertEqual(videoSelection.attachment.id, video.id)
    XCTAssertEqual(videoSelection.attachment.url, video.url)
  }

  @MainActor
  func testFailedTextMessageShowsFriendlyErrorAndRetriesWithoutDuplicate() async throws {
    let client = StubInstaChatClient()
    client.textResults = [
      .failure(URLError(.notConnectedToInternet)),
      .success(())
    ]
    let store = InstaChatStore(
      configuration: Self.testConfiguration(),
      client: client,
      pendingStore: Self.temporaryPendingStore()
    )

    await store.sendText("Hello", roomID: "room-1")

    let message = try XCTUnwrap(store.messages(for: "room-1").first)
    guard case let .failed(failure) = store.deliveryState(for: message.id) else {
      return XCTFail("Expected failed delivery state")
    }
    XCTAssertEqual(failure.message, "No internet connection. Reconnect, then retry your message.")
    XCTAssertNil(store.errorMessage)
    XCTAssertEqual(client.sendTextCallCount, 1)

    await store.retryMessage(messageID: message.id)

    XCTAssertEqual(client.sendTextCallCount, 2)
    XCTAssertNil(store.deliveryState(for: message.id))
    XCTAssertEqual(store.messages(for: "room-1").count, 1)
  }

  @MainActor
  func testVideoRetryReusesSuccessfulUploadAndDoesNotDuplicateBubble() async throws {
    let client = StubInstaChatClient()
    client.uploadResults = [.success(Self.attachment(type: .video, fileName: "clip.mp4", contentType: "video/mp4"))]
    client.attachmentSendResults = [
      .failure(InstaChatError.websocketClosed),
      .success(())
    ]
    let pendingStore = Self.temporaryPendingStore()
    let store = InstaChatStore(configuration: Self.testConfiguration(), client: client, pendingStore: pendingStore)
    let videoURL = try Self.temporaryMediaFile(name: "clip.mp4")

    await store.sendAttachment(fileURL: videoURL, roomID: "room-video", contentType: "video/mp4")

    let message = try XCTUnwrap(store.messages(for: "room-video").first)
    guard case let .failed(failure) = store.deliveryState(for: message.id) else {
      return XCTFail("Expected failed video delivery state")
    }
    XCTAssertEqual(failure.message, "Chat is reconnecting. Retry your video in a moment.")
    XCTAssertEqual(client.uploadCallCount, 1)
    XCTAssertEqual(client.sendAttachmentCallCount, 1)

    await store.retryMessage(messageID: message.id)

    XCTAssertEqual(client.uploadCallCount, 1, "Retry must reuse the uploaded attachment")
    XCTAssertEqual(client.sendAttachmentCallCount, 2)
    XCTAssertNil(store.deliveryState(for: message.id))
    XCTAssertEqual(store.messages(for: "room-video").count, 1)
  }

  @MainActor
  func testFailedVoiceNoteRestoresAfterReopeningAndCanRetry() async throws {
    let pendingStore = Self.temporaryPendingStore()
    let failingClient = StubInstaChatClient()
    failingClient.uploadResults = [.failure(URLError(.networkConnectionLost))]
    let firstStore = InstaChatStore(
      configuration: Self.testConfiguration(),
      client: failingClient,
      pendingStore: pendingStore
    )
    let voiceURL = try Self.temporaryMediaFile(name: "voice-note.m4a")

    await firstStore.sendAttachment(fileURL: voiceURL, roomID: "room-voice", contentType: "audio/mp4")
    let failedMessageID = try XCTUnwrap(firstStore.messages(for: "room-voice").first?.id)

    let retryClient = StubInstaChatClient()
    retryClient.uploadResults = [.success(Self.attachment(type: .audio, fileName: "voice-note.m4a", contentType: "audio/mp4"))]
    retryClient.attachmentSendResults = [.success(())]
    let reopenedStore = InstaChatStore(
      configuration: Self.testConfiguration(),
      client: retryClient,
      pendingStore: pendingStore
    )

    XCTAssertEqual(reopenedStore.messages(for: "room-voice").count, 1)
    guard case .failed = reopenedStore.deliveryState(for: failedMessageID) else {
      return XCTFail("Expected the failed voice note to be restored")
    }

    await reopenedStore.retryMessage(messageID: failedMessageID)

    XCTAssertEqual(retryClient.uploadCallCount, 1)
    XCTAssertEqual(retryClient.sendAttachmentCallCount, 1)
    XCTAssertNil(reopenedStore.deliveryState(for: failedMessageID))
    XCTAssertEqual(reopenedStore.messages(for: "room-voice").count, 1)
  }

  @MainActor
  func testBackendEchoReplacesFailedLocalMessageAndClearsRetryState() async throws {
    let client = StubInstaChatClient()
    client.textResults = [.failure(InstaChatError.websocketClosed)]
    let store = InstaChatStore(
      configuration: Self.testConfiguration(),
      client: client,
      pendingStore: Self.temporaryPendingStore()
    )
    await store.sendText("Delivered despite response failure", roomID: "room-1")
    let localMessage = try XCTUnwrap(store.messages(for: "room-1").first)

    let serverMessage = Self.message(
      id: "server-message",
      roomID: "room-1",
      senderID: "user-1",
      content: localMessage.content,
      createdAt: localMessage.createdAt.addingTimeInterval(1)
    )
    store.applyRealtimeEvent(.message(serverMessage))

    XCTAssertEqual(store.messages(for: "room-1").map(\.id), ["server-message"])
    XCTAssertNil(store.deliveryState(for: localMessage.id))
  }

  @MainActor
  func testVoiceUploadBackendEchoAndImmediatePlaybackUsesLocalCache() async throws {
    let remoteURL = URL(string: "https://instachat.instakit.pro/uploads/voice-\(UUID().uuidString).m4a")!
    let uploadedAttachment = InstaChatAttachment(
      id: "uploaded-voice",
      fileName: "voice-note.m4a",
      contentType: "audio/mp4",
      type: .audio,
      url: remoteURL
    )
    let client = StubInstaChatClient()
    client.uploadResults = [.success(uploadedAttachment)]
    client.attachmentSendResults = [.success(())]
    let store = InstaChatStore(
      configuration: Self.testConfiguration(),
      client: client,
      pendingStore: Self.temporaryPendingStore()
    )
    let recordingData = Data("recorded-voice-note".utf8)
    let recordingURL = try Self.temporaryMediaFile(name: "voice-note.m4a", data: recordingData)

    await store.sendAttachment(fileURL: recordingURL, roomID: "room-voice", contentType: "audio/mp4")
    let localMessage = try XCTUnwrap(store.messages(for: "room-voice").first)
    let backendEcho = Self.message(
      id: "backend-voice",
      roomID: "room-voice",
      senderID: "user-1",
      content: uploadedAttachment.fileName,
      type: .file,
      createdAt: localMessage.createdAt.addingTimeInterval(0.1),
      attachment: uploadedAttachment
    )
    store.applyRealtimeEvent(.message(backendEcho))

    StubMediaURLProtocol.reset(statusCodes: [500])
    let mediaSession = Self.mediaTestSession()
    defer { mediaSession.invalidateAndCancel() }
    let cachedURL = try await AuthenticatedMediaCache.shared.localFileURL(
      for: remoteURL,
      authToken: "token",
      fileName: uploadedAttachment.fileName,
      session: mediaSession
    )

    XCTAssertEqual(store.messages(for: "room-voice").map(\.id), ["backend-voice"])
    XCTAssertEqual(try Data(contentsOf: cachedURL), recordingData)
    XCTAssertEqual(StubMediaURLProtocol.requestCount, 0, "Immediate playback must not download the new voice note")
  }

  @MainActor
  func testVideoUploadBackendEchoAndImmediatePlaybackUsesLocalCache() async throws {
    let remoteURL = URL(string: "https://instachat.instakit.pro/uploads/video-\(UUID().uuidString).mp4")!
    let uploadedAttachment = InstaChatAttachment(
      id: "uploaded-video",
      fileName: "outgoing-video.mp4",
      contentType: "video/mp4",
      type: .video,
      url: remoteURL
    )
    let client = StubInstaChatClient()
    client.uploadResults = [.success(uploadedAttachment)]
    client.attachmentSendResults = [.success(())]
    let store = InstaChatStore(
      configuration: Self.testConfiguration(),
      client: client,
      pendingStore: Self.temporaryPendingStore()
    )
    let videoData = Data("locally-recorded-video".utf8)
    let videoURL = try Self.temporaryMediaFile(name: "outgoing-video.mp4", data: videoData)

    await store.sendAttachment(fileURL: videoURL, roomID: "room-video", contentType: "video/mp4")
    let localMessage = try XCTUnwrap(store.messages(for: "room-video").first)
    let backendEcho = Self.message(
      id: "backend-video",
      roomID: "room-video",
      senderID: "user-1",
      content: uploadedAttachment.fileName,
      type: .file,
      createdAt: localMessage.createdAt.addingTimeInterval(0.1),
      attachment: uploadedAttachment
    )
    store.applyRealtimeEvent(.message(backendEcho))

    StubMediaURLProtocol.reset(statusCodes: [500])
    let mediaSession = Self.mediaTestSession()
    defer { mediaSession.invalidateAndCancel() }
    let source = try await VideoPlaybackSourceResolver.resolve(
      remoteURL: remoteURL,
      fileName: uploadedAttachment.fileName,
      authToken: "token",
      session: mediaSession,
      retryDelaysNanoseconds: []
    )

    XCTAssertEqual(store.messages(for: "room-video").map(\.id), ["backend-video"])
    XCTAssertTrue(source.isLocal)
    XCTAssertEqual(try Data(contentsOf: source.url), videoData)
    XCTAssertEqual(StubMediaURLProtocol.requestCount, 0, "Outgoing video playback must use the preserved local file")
  }

  @MainActor
  func testReceivedProviderVideoStreamsAfterTransientFirstOpenResponses() async throws {
    let remoteURL = URL(string: "https://cdn.example.com/provider-video-\(UUID().uuidString).mp4")!
    let attachment = InstaChatAttachment(
      id: "provider-video",
      fileName: "provider-video.mp4",
      contentType: "video/mp4",
      type: .video,
      url: remoteURL
    )
    let store = InstaChatStore(
      configuration: Self.testConfiguration(),
      pendingStore: Self.temporaryPendingStore()
    )
    store.append(Self.message(
      id: "provider-message",
      roomID: "room-provider",
      senderID: "provider-345",
      content: attachment.fileName,
      type: .file,
      createdAt: Self.date(1),
      attachment: attachment
    ), replacingLocalEcho: false)

    StubMediaURLProtocol.reset(statusCodes: [400, 400, 206])
    let mediaSession = Self.mediaTestSession()
    defer { mediaSession.invalidateAndCancel() }
    let receivedAttachment = try XCTUnwrap(store.messages(for: "room-provider").first?.attachment)
    let source = try await VideoPlaybackSourceResolver.resolve(
      remoteURL: receivedAttachment.url,
      fileName: receivedAttachment.fileName,
      authToken: "provider-token",
      session: mediaSession,
      retryDelaysNanoseconds: [0, 0]
    )

    XCTAssertFalse(source.isLocal)
    XCTAssertEqual(source.url, remoteURL)
    XCTAssertEqual(source.httpHeaders["Authorization"], "Bearer provider-token")
    XCTAssertEqual(StubMediaURLProtocol.requestCount, 3)
    XCTAssertEqual(StubMediaURLProtocol.requestMethods, ["HEAD", "HEAD", "HEAD"])
    XCTAssertEqual(
      StubMediaURLProtocol.authorizationHeaders,
      ["Bearer provider-token", "Bearer provider-token", "Bearer provider-token"]
    )
  }

  func testMediaRetryWindowCoversDelayedCDNAvailability() {
    let totalDelay = MediaRetryPolicy.defaultRetryDelaysNanoseconds.reduce(0, +)

    XCTAssertGreaterThanOrEqual(totalDelay, 15_000_000_000)
    XCTAssertEqual(MediaRetryPolicy.defaultRetryDelaysNanoseconds.count + 1, 6)
  }

  func testTransientMediaDownloadRetriesWithExponentialBackoff() async throws {
    let remoteURL = URL(string: "https://cdn.example.com/voice-\(UUID().uuidString).m4a")!
    StubMediaURLProtocol.reset(statusCodes: [400, 404, 200], responseData: Data("cdn-audio".utf8))
    let mediaSession = Self.mediaTestSession()
    defer { mediaSession.invalidateAndCancel() }

    let localURL = try await AuthenticatedMediaCache.shared.localFileURL(
      for: remoteURL,
      authToken: "token",
      fileName: "voice-note.m4a",
      session: mediaSession,
      retryDelaysNanoseconds: [0, 0]
    )

    XCTAssertEqual(StubMediaURLProtocol.requestCount, 3)
    XCTAssertEqual(try Data(contentsOf: localURL), Data("cdn-audio".utf8))
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

  private static func temporaryPendingStore() -> PendingOutgoingMessageStore {
    PendingOutgoingMessageStore(
      fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("InstaChatTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("pending.json")
    )
  }

  private static func temporaryMediaFile(name: String, data: Data = Data("test-media".utf8)) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstaChatTests-\(UUID().uuidString)-\(name)")
    try data.write(to: url, options: .atomic)
    return url
  }

  private static func mediaTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubMediaURLProtocol.self]
    return URLSession(configuration: configuration)
  }
}

private final class StubInstaChatClient: InstaChatClientProtocol, @unchecked Sendable {
  var textResults: [Result<Void, Error>] = []
  var uploadResults: [Result<InstaChatAttachment, Error>] = []
  var attachmentSendResults: [Result<Void, Error>] = []
  private(set) var sendTextCallCount = 0
  private(set) var uploadCallCount = 0
  private(set) var sendAttachmentCallCount = 0

  func getRooms() async throws -> [InstaChatRoom] { [] }

  func getMessages(roomID: String, limit: Int?, cursor: String?) async throws -> InstaChatMessagesPage {
    InstaChatMessagesPage(messages: [], nextCursor: nil, hasMore: false)
  }

  func uploadAttachment(fileURL: URL, roomID: String, contentType: String?) async throws -> InstaChatAttachment {
    uploadCallCount += 1
    guard !uploadResults.isEmpty else {
      throw InstaChatError.invalidResponse
    }
    return try uploadResults.removeFirst().get()
  }

  func sendText(_ text: String, roomID: String) async throws {
    sendTextCallCount += 1
    guard !textResults.isEmpty else {
      return
    }
    try textResults.removeFirst().get()
  }

  func sendLocation(_ location: InstaChatLocation, roomID: String) async throws {}

  func sendAttachment(_ attachment: InstaChatAttachment, text: String, roomID: String) async throws {
    sendAttachmentCallCount += 1
    guard !attachmentSendResults.isEmpty else {
      return
    }
    try attachmentSendResults.removeFirst().get()
  }

  func sendTyping(roomID: String, isTyping: Bool) async throws {}

  func realtimeEvents() -> AsyncStream<InstaChatRealtimeEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }

  func disconnect() {}
}

private final class StubMediaURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  private static var statusCodes: [Int] = []
  private static var data = Data()
  private static var count = 0
  private static var methods: [String] = []
  private static var authorizations: [String] = []

  static var requestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  static var requestMethods: [String] {
    lock.lock()
    defer { lock.unlock() }
    return methods
  }

  static var authorizationHeaders: [String] {
    lock.lock()
    defer { lock.unlock() }
    return authorizations
  }

  static func reset(statusCodes: [Int], responseData: Data = Data()) {
    lock.lock()
    self.statusCodes = statusCodes
    data = responseData
    count = 0
    methods = []
    authorizations = []
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    let index = Self.count
    Self.count += 1
    Self.methods.append(request.httpMethod ?? "GET")
    Self.authorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
    let statusCode = Self.statusCodes.indices.contains(index) ? Self.statusCodes[index] : 500
    let responseData = Self.data
    Self.lock.unlock()

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "audio/mp4"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if (200..<300).contains(statusCode) {
      client?.urlProtocol(self, didLoad: responseData)
    }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private extension Data {
  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
