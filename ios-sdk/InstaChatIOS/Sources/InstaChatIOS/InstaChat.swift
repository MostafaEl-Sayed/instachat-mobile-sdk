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
    let controller = UIHostingController(rootView: InstaChatView(configuration: configuration))
    viewController.present(controller, animated: true)
  }
  #endif
}

public struct InstaChatView: View {
  @StateObject private var store: InstaChatStore

  public init(configuration: InstaChatConfiguration) {
    _store = StateObject(wrappedValue: InstaChatStore(configuration: configuration))
  }

  public var body: some View {
    NavigationStack {
      ChatRoomListView()
        .environmentObject(store)
    }
    .task {
      store.start()
      await store.loadRooms()
    }
  }
}
