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

To start from a Grandizar/provider ID, the consuming app should call its own backend first, then pass the returned room to the SDK:

```swift
let sdk = InstaChat.initialize(baseURL: instaChatBaseURL, token: token, user: user)
let roomID = try await grandizarBackend.startChat(providerID: "345", token: token)
sdk.chatView(roomID: roomID, title: "Support")
```

The SDK owns chat UI, websocket messages, media, voice notes, and location sharing after a `room_id` exists. The consuming app owns app-specific provider routing, such as `POST /api/v1/user-app/chats/start`.

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

The React Native package remains available for React Native host apps. Native Android apps should use the Kotlin/Compose package described below; they do not need to embed a React Native runtime.

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

Add native permissions for microphone, photos/media, and location in your host app. The native iOS SDK owns photo/video picking, current-location lookup, voice-note recording, and sending. Location sharing requests `When In Use` permission, reads the current device coordinate, reverse-geocodes a display name when available, and sends the backend `location` payload.

Media rules in the native iOS SDK:

- Photo picker allows up to 5 images in one selection and sends them as separate image messages.
- Video picker allows one video per send.
- Videos must be 60 seconds or shorter.
- Large valid videos are compressed before upload when possible; videos over the SDK upload guard are rejected before the backend request.

Text links in the native iOS SDK:

- `http://` and `https://` URLs inside text messages are detected in realtime and historical messages.
- Links keep the existing bubble alignment and sender/receiver styling, with underline/link color applied to the URL range.
- Taps use the standard iOS URL opener, including universal-link handoff for supported Grandizar routes such as `/provider-details/{providerId}`.

Failed outgoing messages in the native iOS SDK remain visible with an inline, user-friendly explanation and Retry button. Text and media retry state survives navigating away or recreating the SDK view, and late backend echoes reconcile with the local bubble rather than creating duplicates.

Room-list previews never expose attachment filenames. Optimistic sends, realtime events, and historical room responses use consistent labels: `Photo`, `Video`, `Voice note`, `File`, and `Location`. Plain text messages continue to show their message text.

Newly sent native iOS voice notes play from the preserved local recording while the CDN copy propagates. Transient media download failures retry automatically with short exponential backoff and then present a clear playback Retry control if the media is still unavailable.

Native iOS image and video previews retain the exact tapped message/attachment identity even when the chat list recycles rows. Media loading is keyed by URL, mixed image/video/voice histories remain chronologically ordered, and the full voice-note row is available as the playback target.

Native iOS remote videos stream through `AVURLAsset` rather than waiting for a full-file download. Readiness uses `GET` with `Range: bytes=0-1`, accepts `200`/`206`, and avoids relying on `HEAD`. Transient CDN readiness failures use a bounded 15.5-second retry window and the preview provides a visible Retry action.

Media authorization is origin-scoped. The SDK sends `Authorization: Bearer <token>` only when the image, audio, video, or file URL has the same scheme, host, and effective port as the configured InstaChat API URL. Direct CDN and presigned URLs receive no chat authorization header. This rule applies to initial loads, retries, Range probes, downloads, and `AVURLAsset` playback, preventing both DigitalOcean `InvalidArgument` responses and cross-host token disclosure.

Outgoing media reconciliation tolerates changed backend attachment IDs and final CDN URLs. Stable media metadata replaces the optimistic message once, and the preserved local upload is re-keyed to the final URL so newly sent videos play locally with zero CDN wait. Received media that remains unavailable after SDK retries must be held by the backend until its CDN `GET` or Range request succeeds with `200`/`206`.

Native iOS image loading validates CDN status codes and retries transient `400`, `404`, `408`, `425`, `429`, `5xx`, and connection failures with the same bounded media policy. A failed thumbnail or full-screen image exposes an inline Retry action, so users do not need to leave and reopen the chat.

Loaded native iOS images use a bounded decoded-image memory cache plus the authenticated disk media cache. Scrolling a loaded bubble off screen and back does not restart its request or show a loader, while chat reopen can reuse the disk copy. Outgoing images are cached during upload reconciliation, and corrupt cache entries are removed before Retry.

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

Add JitPack and the native Android artifact:

```kotlin
maven("https://jitpack.io")
implementation("com.github.MostafaEl-Sayed:instachat-mobile-sdk:0.2.1")
```

Initialize once, then open either the room list or a specific room:

```kotlin
import pro.instakit.instachat.android.InstaChat
import pro.instakit.instachat.android.InstaChatUser

val chat = InstaChat.initialize(
  context = applicationContext,
  baseUrl = "https://instachat.instakit.pro",
  token = instaChatToken,
  user = InstaChatUser(id = user.id, name = user.name, avatarUrl = user.avatarUrl),
)

chat.openChatList(activity)
chat.openChat(activity, roomId = roomId, title = "Support")
```

The host app owns obtaining/refreshing the user token and, for provider-specific flows, calling its own start-chat endpoint to obtain `room_id`. The SDK owns the full chat presentation and close control after either open method is called. See [`android-sdk/README.md`](android-sdk/README.md) for Compose, Java, local-source, and sample instructions.

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

The iOS side presents `InstaChatIOS`; Android invokes the native `InstaChatAndroid` entry points shown above.

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
