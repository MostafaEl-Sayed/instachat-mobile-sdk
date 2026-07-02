// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "InstaChatIOS",
  platforms: [
    .iOS(.v16),
    .macOS(.v13)
  ],
  products: [
    .library(name: "InstaChatIOS", targets: ["InstaChatIOS"])
  ],
  targets: [
    .target(
      name: "InstaChatIOS",
      path: "ios-sdk/InstaChatIOS/Sources/InstaChatIOS"
    ),
    .testTarget(
      name: "InstaChatIOSTests",
      dependencies: ["InstaChatIOS"],
      path: "ios-sdk/InstaChatIOS/Tests/InstaChatIOSTests"
    )
  ]
)
