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
    .target(name: "InstaChatIOS"),
    .testTarget(name: "InstaChatIOSTests", dependencies: ["InstaChatIOS"])
  ]
)
