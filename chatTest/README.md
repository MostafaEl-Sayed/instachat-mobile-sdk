# chatTest

Small native SwiftUI iOS app for validating the `InstaChatIOS` SDK integration.

The sample project depends on the local Swift package at `../ios-sdk/InstaChatIOS`, so cloning this repository and opening `chatTest` validates the exact SDK source in the repo.

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
INSTACHAT_AUTO_OPEN_CHAT=1
```

## What It Shows

- Native SwiftUI home screen.
- Editable `baseURL` and `token`.
- One-button chat launch.
- Direct dependency on the local Swift Package product `InstaChatIOS`.

The integration code is intentionally small:

```swift
import InstaChatIOS

InstaChatView(
  configuration: InstaChatConfiguration(
    baseURL: URL(string: "https://instachat.instakit.pro")!,
    token: token,
    user: InstaChatUser(id: "user-1", name: "Mostafa")
  )
)
```

For production, the native app should inject the authenticated user token from its own login/session flow.

To integrate from GitHub in another native iOS app, add this Swift Package URL in Xcode:

```txt
https://github.com/MostafaEl-Sayed/instachat-mobile-sdk.git
```
