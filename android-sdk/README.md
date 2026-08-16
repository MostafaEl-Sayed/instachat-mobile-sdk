# InstaChatAndroid

Native Kotlin/Jetpack Compose chat SDK for Android 7.0 (API 24) and newer.

## Install From The Private Repository

Download `instachat-android-maven-0.3.3.zip` from the private repository's
[`v0.3.3` release](https://github.com/MostafaEl-Sayed/instachat-android-sdk/releases/tag/v0.3.3),
then extract its `sdk-repository` directory into the host project root. Add the
local Maven repository to `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
  repositories {
    google()
    mavenCentral()
    maven { url = uri("$rootDir/sdk-repository") }
  }
}
```

Add the SDK to the app module:

```kotlin
dependencies {
  implementation("pro.instakit:instachat-android:0.3.3")
}
```

The library manifest contributes internet, microphone, and foreground-location permissions. The host app controls when runtime microphone and location permission prompts are shown.

The Maven archive is preferred over copying the standalone AAR because it
retains the SDK's dependency metadata. GitHub Packages can replace this local
repository after package publishing is enabled for the private repository.

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

For an embedded Compose surface, the room list is shown immediately. A close action is optional because the host owns only presentation:

```kotlin
chat.ChatList(modifier = Modifier.fillMaxSize())
chat.Chat(roomId = roomId, modifier = Modifier.fillMaxSize())
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
includeBuild("../instachat-android-sdk") {
  dependencySubstitution {
    substitute(module("pro.instakit:instachat-android")).using(project(":instachat"))
  }
}
```

Then depend on `pro.instakit:instachat-android:0.3.3`.

The packaged Maven repository is the setup used by the Grandizar integrations.

## SDK Ownership

The SDK owns room loading, room navigation, realtime events, message reconciliation, media upload and caching, voice recording/playback, location sharing, retries, and error UI. Host applications provide only the base URL, authenticated token, user identity, and presentation container.

Selected outgoing media is copied into SDK-managed storage before upload. Image, video, and voice playback prefer that local copy after the backend echo arrives. Remote CDN media is cached, retried for transient `400`, `404`, `408`, `425`, `429`, and `5xx` responses, and receives the bearer token only when the media URL has the same origin as the API base URL.

## Run The Sample

```sh
cd android-sdk
./gradlew :instachat:testDebugUnitTest :sample:assembleDebug
adb install -r sample/build/outputs/apk/debug/sample-debug.apk
```

Open **InstaChat Sample**, paste a valid user token, and choose **Open chat list**. The sample never stores a token in source control.
