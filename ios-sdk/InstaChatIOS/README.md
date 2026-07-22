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

    sdk.chatListView()
  }
}
```

Open a specific room directly:

```swift
sdk.chatView(roomID: "room-id", title: "Support")
```

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
