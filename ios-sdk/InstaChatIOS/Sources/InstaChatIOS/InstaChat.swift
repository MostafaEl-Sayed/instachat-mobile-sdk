import SwiftUI

#if os(iOS)
import UIKit
#endif

public enum InstaChat {
  #if os(iOS)
  @MainActor
  public static func present(
    from viewController: UIViewController,
    baseURL: URL,
    token: String,
    user: InstaChatUser,
    roomID: String? = nil
  ) {
    let configuration = InstaChatConfiguration(baseURL: baseURL, token: token, user: user, roomID: roomID)
    var controller: UIHostingController<InstaChatView>?
    let rootView = InstaChatView(configuration: configuration) {
      controller?.dismiss(animated: true)
    }
    controller = UIHostingController(rootView: rootView)
    guard let controller else {
      return
    }
    viewController.present(controller, animated: true)
  }
  #endif
}

public struct InstaChatView: View {
  @StateObject private var store: InstaChatStore
  private let onClose: (() -> Void)?

  public init(configuration: InstaChatConfiguration, onClose: (() -> Void)? = nil) {
    _store = StateObject(wrappedValue: InstaChatStore(configuration: configuration))
    self.onClose = onClose
  }

  public var body: some View {
    NavigationStack {
      ChatRoomListView(onClose: onClose)
        .environmentObject(store)
    }
    .task {
      store.start()
      await store.loadRooms()
    }
  }
}
