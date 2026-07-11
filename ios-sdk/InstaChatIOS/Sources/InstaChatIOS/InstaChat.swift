import SwiftUI

#if os(iOS)
import UIKit
#endif

public enum InstaChat {
  public static func initialize(
    baseURL: URL,
    token: String,
    user: InstaChatUser,
    historyLimit: Int = 25,
    title: String = "Messages"
  ) -> InstaChatSDK {
    InstaChatSDK(baseURL: baseURL, token: token, user: user, historyLimit: historyLimit, title: title)
  }

  #if os(iOS)
  /// Legacy compatibility API. Prefer `InstaChat.initialize(...).presentChatList(from:)`
  /// or `InstaChat.initialize(...).presentChat(from:roomID:)`.
  /// This entry point will be deprecated in a future release.
  @MainActor
  public static func present(
    from viewController: UIViewController,
    baseURL: URL,
    token: String,
    user: InstaChatUser,
    roomID: String? = nil
  ) {
    let sdk = initialize(baseURL: baseURL, token: token, user: user)
    if let roomID {
      sdk.presentChat(from: viewController, roomID: roomID)
    } else {
      sdk.presentChatList(from: viewController)
    }
  }
  #endif
}

public struct InstaChatSDK: Sendable {
  public let configuration: InstaChatConfiguration

  public init(
    baseURL: URL,
    token: String,
    user: InstaChatUser,
    historyLimit: Int = 25,
    title: String = "Messages"
  ) {
    self.configuration = InstaChatConfiguration(
      baseURL: baseURL,
      token: token,
      user: user,
      historyLimit: historyLimit,
      title: title
    )
  }

  public init(configuration: InstaChatConfiguration) {
    self.configuration = InstaChatConfiguration(
      baseURL: configuration.baseURL,
      token: configuration.token,
      user: configuration.user,
      historyLimit: configuration.historyLimit,
      title: configuration.title
    )
  }

  public func chatListView(onClose: (() -> Void)? = nil) -> InstaChatView {
    InstaChatView(configuration: configuration, onClose: onClose)
  }

  public func chatView(roomID: String, title: String? = nil, onClose: (() -> Void)? = nil) -> InstaChatView {
    InstaChatView(configuration: configuration.openingRoom(id: roomID, title: title), onClose: onClose)
  }

  #if os(iOS)
  @MainActor
  public func presentChatList(from viewController: UIViewController) {
    present(from: viewController, configuration: configuration)
  }

  @MainActor
  public func presentChat(from viewController: UIViewController, roomID: String, title: String? = nil) {
    present(from: viewController, configuration: configuration.openingRoom(id: roomID, title: title))
  }

  @MainActor
  private func present(from viewController: UIViewController, configuration: InstaChatConfiguration) {
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

  /// Legacy compatibility initializer. Prefer creating `InstaChatSDK` once with
  /// `InstaChat.initialize(...)`, then call `sdk.chatListView(...)` or
  /// `sdk.chatView(roomID:...)`. This initializer will be deprecated in a future release.
  public init(configuration: InstaChatConfiguration, onClose: (() -> Void)? = nil) {
    _store = StateObject(wrappedValue: InstaChatStore(configuration: configuration))
    self.onClose = onClose
  }

  public var body: some View {
    NavigationStack {
      if let room = store.configuration.initialRoom {
        ChatDetailView(room: room, onClose: onClose)
          .environmentObject(store)
      } else {
        ChatRoomListView(onClose: onClose)
          .environmentObject(store)
      }
    }
    .task {
      store.start()
      if store.configuration.initialRoom == nil {
        await store.loadRooms()
      }
    }
  }
}
