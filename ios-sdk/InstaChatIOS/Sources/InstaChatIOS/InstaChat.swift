import SwiftUI

#if os(iOS)
import GoogleMaps
import UIKit
#endif

public enum InstaChat {
  public static func initialize(
    baseURL: URL,
    token: String,
    user: InstaChatUser,
    historyLimit: Int = 25,
    title: String = "Messages",
    googleMapsAPIKey: String? = nil
  ) -> InstaChatSDK {
    InstaChatSDK(
      baseURL: baseURL,
      token: token,
      user: user,
      historyLimit: historyLimit,
      title: title,
      googleMapsAPIKey: googleMapsAPIKey
    )
  }

  #if os(iOS)
  /// Initializes Google Maps for hosts that create their own Google map before presenting chat.
  /// Apps that only use Google Maps inside InstaChat can omit this call and pass the key to
  /// `initialize`; the SDK will configure Google Maps before constructing the picker.
  @MainActor
  @discardableResult
  public static func configureGoogleMaps(apiKey: String) -> Bool {
    InstaChatGoogleMapsRuntime.configure(apiKey: apiKey)
  }
  #endif

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
    roomID: String? = nil,
    googleMapsAPIKey: String? = nil
  ) {
    let sdk = initialize(
      baseURL: baseURL,
      token: token,
      user: user,
      googleMapsAPIKey: googleMapsAPIKey
    )
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
    title: String = "Messages",
    googleMapsAPIKey: String? = nil
  ) {
    self.configuration = InstaChatConfiguration(
      baseURL: baseURL,
      token: token,
      user: user,
      historyLimit: historyLimit,
      title: title,
      googleMapsAPIKey: googleMapsAPIKey
    )
  }

  public init(configuration: InstaChatConfiguration) {
    self.configuration = configuration
  }

  public func chatListView(
    onClose: (() -> Void)? = nil,
    onProviderProfileTap: ((InstaChatRoom) -> Void)? = nil
  ) -> InstaChatView {
    InstaChatView(configuration: configuration, onClose: onClose, onProviderProfileTap: onProviderProfileTap)
  }

  public func chatView(
    roomID: String,
    title: String? = nil,
    onClose: (() -> Void)? = nil,
    onProviderProfileTap: ((InstaChatRoom) -> Void)? = nil
  ) -> InstaChatView {
    InstaChatView(
      configuration: configuration.openingRoom(id: roomID, title: title),
      onClose: onClose,
      onProviderProfileTap: onProviderProfileTap
    )
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

#if os(iOS)
@MainActor
enum InstaChatGoogleMapsRuntime {
  private static var configuredAPIKey: String?

  @discardableResult
  static func configure(apiKey: String) -> Bool {
    let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedKey.isEmpty else {
      return false
    }
    guard configuredAPIKey == nil else {
      return configuredAPIKey == normalizedKey
    }

    let didConfigure = GMSServices.provideAPIKey(normalizedKey)
    if didConfigure {
      configuredAPIKey = normalizedKey
    }
    return didConfigure
  }
}
#endif

public struct InstaChatView: View {
  @StateObject private var store: InstaChatStore
  @State private var navigationPath = NavigationPath()
#if os(iOS)
  @Environment(\.scenePhase) private var scenePhase
#endif
  private let onClose: (() -> Void)?
  private let onProviderProfileTap: ((InstaChatRoom) -> Void)?

  /// Legacy compatibility initializer. Prefer creating `InstaChatSDK` once with
  /// `InstaChat.initialize(...)`, then call `sdk.chatListView(...)` or
  /// `sdk.chatView(roomID:...)`. This initializer will be deprecated in a future release.
  public init(
    configuration: InstaChatConfiguration,
    onClose: (() -> Void)? = nil,
    onProviderProfileTap: ((InstaChatRoom) -> Void)? = nil
  ) {
    _store = StateObject(wrappedValue: InstaChatStore(configuration: configuration))
    self.onClose = onClose
    self.onProviderProfileTap = onProviderProfileTap
  }

  public var body: some View {
    NavigationStack(path: $navigationPath) {
      if let room = store.configuration.initialRoom {
        ChatDetailView(room: room, onClose: onClose, onProviderProfileTap: onProviderProfileTap)
          .environmentObject(store)
      } else {
        ChatRoomListView(onClose: onClose, onProviderProfileTap: onProviderProfileTap)
          .environmentObject(store)
      }
    }
#if os(iOS)
    .background {
      HostTabBarVisibilityBridge(
        isHidden: store.configuration.initialRoom != nil || !navigationPath.isEmpty
      )
      .frame(width: 0, height: 0)
    }
#endif
    .task {
      store.start()
      if store.configuration.initialRoom == nil {
        await store.loadRooms()
      }
    }
#if os(iOS)
    .onChange(of: scenePhase) { phase in
      guard phase == .active else {
        return
      }
      Task {
        await store.refreshAfterForeground()
      }
    }
#endif
  }
}
