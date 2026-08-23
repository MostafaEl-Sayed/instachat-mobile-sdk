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
  dependencies: [
    .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "9.4.0")
  ],
  targets: [
    .target(
      name: "InstaChatIOS",
      dependencies: [
        .product(
          name: "GoogleMaps",
          package: "ios-maps-sdk",
          condition: .when(platforms: [.iOS])
        )
      ]
    ),
    .testTarget(name: "InstaChatIOSTests", dependencies: ["InstaChatIOS"])
  ]
)
