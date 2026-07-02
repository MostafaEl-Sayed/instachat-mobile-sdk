import React
import SwiftUI
import UIKit

struct ChatSDKNativeConfiguration {
  let baseURL: URL
  let token: String
  let userID: String
  let userName: String
  let headerTitle: String
  let placeholderText: String

  static let `default` = ChatSDKNativeConfiguration(
    baseURL: URL(string: "https://instachat.instakit.pro")!,
    token: "",
    userID: "user-1",
    userName: "User-1: Bookshy",
    headerTitle: "Messages",
    placeholderText: "Message"
  )

  var initialProperties: [String: Any] {
    [
      "baseUrl": baseURL.absoluteString,
      "token": token,
      "userId": userID,
      "userName": userName,
      "headerTitle": headerTitle,
      "placeholderText": placeholderText
    ]
  }
}

struct ReactNativeChatView: UIViewRepresentable {
  let configuration: ChatSDKNativeConfiguration

  func makeUIView(context: Context) -> RCTRootView {
    RCTRootView(
      bundleURL: Self.bundleURL(),
      moduleName: "main",
      initialProperties: configuration.initialProperties,
      launchOptions: nil
    )
  }

  func updateUIView(_ uiView: RCTRootView, context: Context) {
    uiView.appProperties = configuration.initialProperties
  }

  private static func bundleURL() -> URL {
    #if DEBUG
    return RCTBundleURLProvider.sharedSettings().jsBundleURL(
      forBundleRoot: ".expo/.virtual-metro-entry",
      fallbackExtension: "jsbundle"
    )
    #else
    return Bundle.main.url(forResource: "main", withExtension: "jsbundle")!
    #endif
  }
}
