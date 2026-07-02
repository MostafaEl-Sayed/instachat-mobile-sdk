import SwiftUI
import UIKit

@objc(ChatExampleRootFactory)
final class ChatExampleRootFactory: NSObject {
  @objc static func makeRootViewController() -> UIViewController {
    UIHostingController(rootView: ChatExampleHomeView())
  }
}
