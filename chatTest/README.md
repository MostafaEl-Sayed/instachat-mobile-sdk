# chatTest

Small native SwiftUI iOS app for validating the `InstaChatIOS` SDK integration.

The sample project depends on the public Swift Package at `https://github.com/MostafaEl-Sayed/instachat-mobile-sdk.git` starting from `v0.1.29`.

## Open

```sh
cd chatTest
xcodegen generate
open chatTest.xcodeproj
```

Select the `chatTest` scheme and run on an iPhone simulator or device.

For local validation without committing credentials, pass launch environment values:

```sh
INSTACHAT_TOKEN="<user-jwt>"
GRANDIZAR_BACKEND_BASE_URL="https://your-grandizar-app-backend.example"
GRANDIZAR_PROVIDER_ID="345"
INSTACHAT_AUTO_OPEN_CHAT=1
```

## What It Shows

- Native SwiftUI home screen.
- Editable `baseURL` and `token`.
- Host-app start-chat flow: Grandizar backend returns `room_id`, then the SDK opens that room.
- One-button chat launch.
- SDK-owned photo, video, location, and real voice-note controls.
- Generic room-list media previews that never display uploaded filenames.
- Exact image/video preview selection, including mixed-media conversations and recycled list rows.
- Streamed remote video playback with origin-scoped authentication, delayed-CDN retry, and an explicit preview Retry button.
- Immediate local playback for newly sent videos while their CDN copy becomes available.
- Outgoing media reconciliation across changed backend attachment IDs/URLs, preserving immediate local video playback.
- Remote video readiness checks use `GET` with `Range: bytes=0-1`, accepting `200` and `206` instead of relying on `HEAD`.
- External CDN media omits the InstaChat bearer token; same-origin API media proxies retain it.
- Image loading includes transient CDN retry and an inline Retry action that does not require reopening chat.
- Decoded-memory and authenticated-disk image caching, preventing loaders and repeated requests when scrolling through previously loaded messages.
- Persistent inline failure states and retry for text, video, voice-note, and other outgoing messages.
- Direct dependency on the local Swift Package product `InstaChatIOS`.

The integration code is intentionally small:

```swift
import InstaChatIOS

let sdk = InstaChat.initialize(
  baseURL: URL(string: "https://instachat.instakit.pro")!,
  token: token,
  user: InstaChatUser(id: "user-1", name: "Mostafa")
)

// Option A: open the SDK chat list.
sdk.chatListView()

// Option B: host app starts a provider chat first, then opens the returned room.
let roomID = try await grandizarBackend.startChat(providerID: "345", token: token)
sdk.chatView(roomID: roomID, title: "Support")
```

For production, the native app should inject the authenticated user token from its own login/session flow. The host app owns presentation state and any app-backend workflow such as `POST /api/v1/user-app/chats/start`; the SDK renders the close button and handles normal chat once a `room_id` exists.

To integrate from GitHub in another native iOS app, add this Swift Package URL in Xcode:

```txt
https://github.com/MostafaEl-Sayed/instachat-mobile-sdk.git
```
