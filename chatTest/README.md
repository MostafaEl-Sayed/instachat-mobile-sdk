# chatTest

Small native SwiftUI iOS app for validating the `InstaChatIOS` SDK integration.

## Open

```sh
cd chatTest
xcodegen generate
open chatTest.xcodeproj
```

Select the `chatTest` scheme and run on an iPhone simulator or device.

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
