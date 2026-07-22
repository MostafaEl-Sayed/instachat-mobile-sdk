# react-native-chat-sdk

Reusable React Native chat SDK for iOS and Android hosts. The SDK renders chat UI, room lists, realtime WebSocket messages, typing, media, voice notes, and location sharing. The `/example` app is a native SwiftUI iOS host that embeds the React Native SDK view.

## Native iOS SDK

Native iOS apps should use the Swift Package product `InstaChatIOS`. This is the clean integration path for SwiftUI/UIKit teams because it does not require a React Native host view.

In Xcode:

1. Select **File > Add Package Dependencies**.
2. Paste the GitHub repo URL.
3. Add the `InstaChatIOS` product to your iOS app target.

There is also a minimal native SwiftUI sample app in `chatTest/`. It is intentionally small for native iOS teams:

```sh
cd chatTest
xcodegen generate
open chatTest.xcodeproj
```

Run the `chatTest` scheme, initialize the SDK, then open either the chat list or a specific room.

SwiftUI:

```swift
import InstaChatIOS

let sdk = InstaChat.initialize(
  baseURL: URL(string: "https://instachat.instakit.pro")!,
  token: token,
  user: InstaChatUser(id: "user-1", name: "Mostafa")
)

sdk.chatListView()
sdk.chatView(roomID: "room-id", title: "Support")
```

UIKit:

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

Existing `InstaChatView(configuration:)` and `InstaChat.present(from:baseURL:token:user:roomID:)` integrations still work. They are legacy compatibility entry points now; new consumers should initialize with `InstaChat.initialize(...)` because those older entry points will be deprecated in a future release.

The React Native package remains available for React Native host apps. Android should get a separate native Kotlin/Compose package next; embedding React Native inside a native Android app is possible but is not the recommended simple SDK experience.

## Customer Quick Start

For React Native apps, integration is intentionally small: install the package, import `InstaChatSDK`, then pass the backend `baseUrl`, user `token`, and host-app user object.

```sh
npm install react-native-chat-sdk @shopify/flash-list react-native-nitro-modules react-native-nitro-sound
cd ios && pod install
```

```tsx
import { InstaChatSDK } from "react-native-chat-sdk";

export function SupportChat() {
  return (
    <InstaChatSDK
      baseUrl="https://instachat.instakit.pro"
      token={userJwt}
      user={{ id: "user-1", name: "Mostafa" }}
      theme={{ primaryColor: "#007AFF" }}
    />
  );
}
```

Add native permissions for microphone, photos/media, and location in your host app. Media picking and location are adapter-based, so production apps can use their existing native picker/location implementation.

Media rules in the native iOS SDK:

- Photo picker allows up to 5 images in one selection and sends them as separate image messages.
- Video picker allows one video per send.
- Videos must be 60 seconds or shorter.
- Large valid videos are compressed before upload when possible; videos over the SDK upload guard are rejected before the backend request.

## With Host Adapters

```tsx
import { InstaChatSDK } from "react-native-chat-sdk";

<InstaChatSDK
  baseUrl="https://instachat.instakit.pro"
  token={userJwt}
  user={{ id: "user-1", name: "Mostafa" }}
  mediaPickerProvider={mediaPickerProvider}
  locationProvider={locationProvider}
  headerTitle="Messages"
  placeholderText="Message"
/>;
```

The lower-level API is still available when you need complete control:

```tsx
import { ChatSDK, createInstaChatSDKConfig } from "react-native-chat-sdk";

const config = createInstaChatSDKConfig({ baseUrl, token, mediaPickerProvider, locationProvider });

<ChatSDK config={config} user={user} />;
```

## Publish The SDK

Publish this package to npm or your private registry, then send customers the install command and quick-start snippet above.

```sh
npm version patch
npm publish --access public
```

For a private SDK, publish to a private npm registry or GitHub Packages and replace the install command with your scoped package name, for example `npm install @instakit/react-native-chat-sdk`.

## SwiftUI iOS Host

This package is a React Native SDK. A pure Swift app can use it, but it must host a React Native root view. The example app already demonstrates the native SwiftUI shell and floating button presentation.

Embed the SDK in a SwiftUI app through `RCTRootView`. The example project does this in:

- `example/ios/ChatSDKExample/ChatExampleHomeView.swift`
- `example/ios/ChatSDKExample/ReactNativeChatView.swift`

Minimal SwiftUI wrapper:

```swift
import React
import SwiftUI

struct ReactNativeChatView: UIViewRepresentable {
  let baseURL: URL
  let token: String

  func makeUIView(context: Context) -> RCTRootView {
    RCTRootView(
      bundleURL: RCTBundleURLProvider.sharedSettings()
        .jsBundleURL(forBundleRoot: ".expo/.virtual-metro-entry", fallbackExtension: "jsbundle"),
      moduleName: "main",
      initialProperties: [
        "baseUrl": baseURL.absoluteString,
        "token": token,
        "userId": "user-1",
        "userName": "Mostafa"
      ],
      launchOptions: nil
    )
  }

  func updateUIView(_ view: RCTRootView, context: Context) {}
}
```

Then present it like any SwiftUI view:

```swift
.sheet(isPresented: $showChat) {
  ReactNativeChatView(baseURL: URL(string: "https://instachat.instakit.pro")!, token: token)
}
```

## Android Kotlin Host

Use a normal React Native host or a dedicated `ReactRootView` in your Android app:

```kotlin
val props = Bundle().apply {
  putString("baseUrl", "https://instachat.instakit.pro")
  putString("token", token)
  putString("userId", "user-1")
  putString("userName", "Mostafa")
}

val rootView = ReactRootView(context)
rootView.startReactApplication(reactNativeHost.reactInstanceManager, "main", props)
setContentView(rootView)
```

## Flutter Host

For Flutter apps, host the SDK in a native screen and open it through a platform channel:

```dart
const chat = MethodChannel("chat_sdk");
await chat.invokeMethod("openChat", {
  "baseUrl": "https://instachat.instakit.pro",
  "token": token,
  "userId": "user-1",
  "userName": "Mostafa",
});
```

The iOS side presents the same SwiftUI `ReactNativeChatView`; Android presents the same `ReactRootView`.

## Backend Contract

`createInstaChatSDKConfig` wires the live InstaChat adapters:

- `GET /api/v1/me/rooms`
- `GET /api/v1/rooms/{room_id}/messages?limit={limit}&cursor={cursor}`
- WebSocket `message.send`
- WebSocket typing events
- `POST /api/v1/rooms/{room_id}/attachments`

Message history is paged. The SDK loads a small initial page, renders the latest message at the bottom immediately, and requests older messages when the user scrolls upward. Providers that do not implement `getMessagesPage` still work through the older `getMessages` compatibility path.

The SDK is cache-first on room open. It renders cached messages immediately when available, then syncs the latest backend page in the background and merges live WebSocket messages into the same cache. By default this uses `MemoryChatCacheProvider`, which is fast but process-local. Production host apps can provide `config.cacheProvider` backed by SQLite, MMKV, AsyncStorage, or their existing storage layer.

Message types supported by send and receive:

```ts
type BackendMessageType = "text" | "image" | "file" | "location";
```

Location content is JSON:

```json
{ "latitude": 30.0444, "longitude": 31.2357, "name": "Cairo" }
```

## UI

The SDK chat list follows iOS-style grouped list behavior: large title, quiet grouped background, rounded rows, circular avatars, unread dots, timestamps, and disclosure affordance. The same React Native UI still runs on Android and can be themed per host app.

## Performance And Framework Decision

The current recommendation is to keep the React Native SDK and harden it before considering Flutter or native rewrites. The observed issues are primarily hybrid embedding, keyboard ownership, media rendering, and lifecycle cleanup problems rather than proven React Native memory leaks.

Current hardening:

- Chat transcript uses FlashList with inverted latest-message rendering.
- Message history is paged with backend cursors instead of loading the full room at once.
- Room open is cache-first, with live backend sync after the initial render.
- Remote images lazy-load in fixed-size bubbles with placeholders; media is not eagerly prefetched on room open.
- WebSocket listeners, pending sends, typing timers, and audio listeners are explicitly cleaned up on unmount/disconnect.
- SwiftUI hosts can choose keyboard ownership through `keyboardAvoidingEnabled`.

Decision gate before migration:

- Test a Release build on a physical iPhone and Android device.
- Profile with Instruments Time Profiler, Allocations, Leaks, Memory Graph, and Core Animation.
- Measure chat list open, chat detail open, keyboard open/close, typing, media-heavy history, voice recording, and voice playback.
- Keep React Native if memory stabilizes after repeated open/close cycles and the transcript/keyboard are smooth.
- Build a pure Swift Package only if native iOS teams require a one-package SwiftUI/UIKit integration. Wrapping React Native or Flutter in Swift Package form is possible, but it is not the clean native SDK experience.
- Do not migrate to Flutter unless Flutter host apps become a first-class customer target; Flutter still embeds a runtime when used inside native iOS/Android apps.

## Run The SwiftUI Example

```sh
npm install
cd example
npm install
npm run ios
```

Open `example/ios/ChatSDKExample.xcworkspace` if you want to inspect the SwiftUI app in Xcode. The example home screen is native SwiftUI and demonstrates:

- Floating chat button
- Bottom sheet chat that expands to full screen
- Full-screen chat presentation
- Base URL passed from Swift into the React Native SDK

Because the SDK records real voice notes with `react-native-nitro-sound`, use a development build or `expo run:ios`; plain Expo Go is not enough.

## Tests

```sh
npm run typecheck
npm run test
npm run test:integration
npm run smoke
cd example && npm run typecheck
```

`npm run test` uses mocked REST and WebSocket layers. `npm run test:integration` hits the live backend and sends small contract probe messages/uploads.
