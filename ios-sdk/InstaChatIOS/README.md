# InstaChatIOS

Native iOS Swift Package for InstaChat.

## Install

In Xcode:

1. Open your iOS app project.
2. Select **File > Add Package Dependencies**.
3. Enter the private GitHub package URL.
4. Add `InstaChatIOS` to your app target.

## SwiftUI Usage

```swift
import InstaChatIOS
import SwiftUI

struct SupportChatScreen: View {
  let token: String

  var body: some View {
    InstaChatView(
      configuration: InstaChatConfiguration(
        baseURL: URL(string: "https://instachat.instakit.pro")!,
        token: token,
        user: InstaChatUser(id: "user-1", name: "Mostafa")
      )
    )
  }
}
```

## UIKit Usage

```swift
import InstaChatIOS

InstaChat.present(
  from: viewController,
  baseURL: URL(string: "https://instachat.instakit.pro")!,
  token: token,
  user: InstaChatUser(id: "user-1", name: "Mostafa")
)
```

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
