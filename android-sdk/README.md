# InstaChatAndroid

Native Kotlin/Jetpack Compose chat SDK for Android 7.0 (API 24) and newer.

## Install

Add JitPack to `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
  repositories {
    google()
    mavenCentral()
    maven("https://jitpack.io")
  }
}
```

Add the SDK to the app module:

```kotlin
dependencies {
  implementation("com.github.MostafaEl-Sayed:instachat-mobile-sdk:v0.2.1")
}
```

The library manifest contributes internet, microphone, and foreground-location permissions. The host app controls when runtime microphone and location permission prompts are shown.

## Initialize Once

Initialize after the host app obtains an InstaChat user token from its backend:

```kotlin
import pro.instakit.instachat.android.InstaChat
import pro.instakit.instachat.android.InstaChatUser

val chat = InstaChat.initialize(
  context = applicationContext,
  baseUrl = "https://instachat.instakit.pro",
  token = instaChatToken,
  user = InstaChatUser(
    id = currentUser.id,
    name = currentUser.name,
    avatarUrl = currentUser.avatarUrl,
  ),
)
```

Do not place a production token in source code or use the normal Grandizar API access token. The host backend must issue the authenticated InstaChat token and refresh it when required.

## Open Chat

The host owns presentation. The SDK owns the room list, chat navigation, close button, realtime connection, composer, media, voice notes, and location UI.

```kotlin
// Show the room list.
chat.openChatList(activity)

// Open a room returned by the host backend's start-chat endpoint.
chat.openChat(activity, roomId = startChatResponse.roomId, title = provider.name)
```

For an embedded Compose surface:

```kotlin
chat.ChatList(onClose = { navigator.closeChat() })
chat.Chat(roomId = roomId, onClose = { navigator.closeChat() })
```

Java hosts use the same entry points:

```java
InstaChatSDK chat = InstaChat.initialize(
    getApplicationContext(),
    "https://instachat.instakit.pro",
    instaChatToken,
    new InstaChatUser(userId, displayName, avatarUrl),
    30,
    "Messages"
);
chat.openChatList(this);
```

Flutter hosts call these methods from the Android side of a platform channel. No Flutter runtime is included in the SDK.

## Local Source Integration

During SDK development, include the repository build:

```kotlin
includeBuild("../instachat-mobile-sdk/android-sdk") {
  dependencySubstitution {
    substitute(module("pro.instakit:instachat-android")).using(project(":instachat"))
  }
}
```

Then depend on `pro.instakit:instachat-android:0.2.1`.

## Run The Sample

```sh
cd android-sdk
./gradlew :instachat:testDebugUnitTest :sample:assembleDebug
adb install -r sample/build/outputs/apk/debug/sample-debug.apk
```

Open **InstaChat Sample**, paste a valid user token, and choose **Open chat list**. The sample never stores a token in source control.
