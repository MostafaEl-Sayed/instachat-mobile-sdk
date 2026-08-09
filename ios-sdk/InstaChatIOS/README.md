# InstaChatIOS

Native iOS Swift Package for InstaChat.

The SDK owns the full chat UI, including room list, chat detail, close button, photo/video picking, location sharing, real voice-note recording, and voice-note playback.

## Install

In Xcode:

1. Open your iOS app project.
2. Select **File > Add Package Dependencies**.
3. Enter the GitHub package URL.
4. Add `InstaChatIOS` to your app target.

## SwiftUI Usage

Initialize the SDK once with the authenticated token, then present either the chat list or a specific room.

```swift
import InstaChatIOS
import SwiftUI

struct SupportChatScreen: View {
  let token: String
  private let baseURL = URL(string: "https://instachat.instakit.pro")!

  var body: some View {
    let sdk = InstaChat.initialize(
      baseURL: baseURL,
      token: token,
      user: InstaChatUser(id: "user-1", name: "Mostafa")
    )

    sdk.chatListView(
      onProviderProfileTap: { room in
        // Navigate to your native provider profile screen.
        openProviderProfile(id: room.providerExternalUserID ?? room.providerID)
      }
    )
  }
}
```

Open a specific room directly:

```swift
sdk.chatView(roomID: "room-id", title: "Support")
```

If the native app needs to start a chat from a provider ID, keep that call in the host app backend. The expected flow is:

```swift
let sdk = InstaChat.initialize(baseURL: instaChatBaseURL, token: token, user: user)
let roomID = try await grandizarBackend.startChat(providerID: "345", token: token)
sdk.chatView(roomID: roomID, title: "Support")
```

The SDK intentionally does not call `POST /api/v1/user-app/chats/start` directly because that endpoint belongs to the consuming app backend. After the backend returns `room_id`, all normal chat behavior runs through the SDK.

The provider name/avatar in the chat header is tappable when `onProviderProfileTap` is supplied. The SDK passes the active `InstaChatRoom`, including `providerID`, `providerExternalUserID`, and `providerProfileURL` when the backend provides them.

`InstaChatView(configuration:)` still works for existing consumers, but it is now a legacy compatibility entry point. Prefer `InstaChat.initialize(...)`; the direct configuration view initializer will be formally deprecated in a future release.

## UIKit Usage

```swift
import InstaChatIOS

let sdk = InstaChat.initialize(
  baseURL: URL(string: "https://instachat.instakit.pro")!,
  token: token,
  user: InstaChatUser(id: "user-1", name: "Mostafa")
)

sdk.presentChatList(from: viewController)
sdk.presentChat(from: viewController, roomID: "room-id", title: "Support")
```

The older `InstaChat.present(from:baseURL:token:user:roomID:)` helper still works, but it is a legacy compatibility API and will be deprecated in a future release.

## Permissions

Add the permissions your host app enables:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Attach photos and videos to chat messages.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Share your current location in chat.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Record voice notes for chat.</string>
```

Location sharing is handled inside the SDK. When the user taps Location, the SDK requests `When In Use` permission if needed, reads the current device coordinate, reverse-geocodes a readable name when available, and sends the backend `location` message payload.

## Media Limits

- Users can select and send up to 5 images at once.
- Users can select one video at a time.
- Videos must be 60 seconds or shorter.
- Large valid videos are compressed before upload when possible. Very large videos are rejected before upload so the UI does not break during backend upload.

## Failed Sends And Retry

Text, photo, video, voice-note, file, and location messages show an inline sending state. If delivery fails, the message remains in the conversation with a clear explanation and a Retry button instead of showing a raw networking alert.

Failed outgoing messages and their local media are stored by the SDK with iOS file protection. They remain retryable after navigating back to the room list, reopening the chat, or recreating the SDK view. A late backend echo replaces the local message and clears its retry state, preventing duplicate bubbles.

Newly recorded voice notes are copied into the authenticated media cache before the local pending upload is released. They can therefore play immediately after the backend echo without waiting for CDN propagation. Remote media downloads retry transient `400`, `404`, rate-limit, server, and connection failures with bounded exponential backoff; playback failures show an explicit Retry control.

Image and video previews are selected by the exact message and attachment identity. Scrolling or SwiftUI row reuse cannot redirect a tap to another media item, and image/video loaders reset whenever the selected URL changes. The complete voice-note row is tappable while playback remains owned by the chat screen, so it continues when its bubble scrolls off screen.

Remote videos stream through `AVURLAsset`/`AVPlayerItem` with the SDK authentication header instead of downloading the complete file before playback. The SDK retries transient CDN readiness responses for up to approximately 15.5 seconds, then keeps the preview open with a clear Retry button. Newly sent videos are copied to the authenticated media cache during upload reconciliation and play from that local copy immediately.

## Text Links

Text messages automatically detect embedded `http://` and `https://` URLs, including multiline and Arabic/right-to-left messages. Links render with underline styling inside the existing sender/receiver bubble design and open through the standard platform URL opener, so Grandizar universal links such as `/provider-details/{providerId}` can route into the app when iOS supports them, while external links open in Safari, the App Store, or the appropriate app.

## Backend

The package uses the live InstaChat backend:

- `GET /api/v1/me/rooms`
- `GET /api/v1/rooms/{room_id}/messages?limit={limit}&cursor={cursor}`
- `POST /api/v1/rooms/{room_id}/attachments`
- `wss://.../ws?token={token}`

Supported message payload types:

```swift
text
image
file
location // content is JSON: { latitude: Double, longitude: Double, name: String? }
```
