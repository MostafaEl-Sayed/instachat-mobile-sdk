#if os(iOS)
import SwiftUI
import UIKit

/// Controls a UIKit tab bar that belongs to the host application. SwiftUI's
/// tab-bar toolbar placement does not reach a UITabBarController when the SDK
/// is embedded as a child UIHostingController.
struct HostTabBarVisibilityBridge: UIViewControllerRepresentable {
  var isHidden: Bool

  func makeUIViewController(context: Context) -> HostTabBarVisibilityViewController {
    HostTabBarVisibilityViewController(isHidden: isHidden)
  }

  func updateUIViewController(
    _ viewController: HostTabBarVisibilityViewController,
    context: Context
  ) {
    viewController.setTabBarHidden(isHidden)
  }

  static func dismantleUIViewController(
    _ viewController: HostTabBarVisibilityViewController,
    coordinator: Void
  ) {
    viewController.restoreTabBarVisibility()
  }
}

@MainActor
final class HostTabBarVisibilityViewController: UIViewController {
  private var shouldHideTabBar: Bool
  private weak var managedTabBarController: UITabBarController?
  private var originalVisibility: Bool?
  private var appliedHiddenState: Bool?
  private let animationDuration: TimeInterval = 0.25

  init(isHidden: Bool) {
    shouldHideTabBar = isHidden
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    self.view = view
  }

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    applyTabBarVisibilityWhenAttached()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    applyTabBarVisibilityWhenAttached()
  }

  func setTabBarHidden(_ isHidden: Bool) {
    shouldHideTabBar = isHidden
    applyTabBarVisibilityWhenAttached()
  }

  func restoreTabBarVisibility() {
    guard let tabBarController = managedTabBarController,
          let originalVisibility else {
      return
    }
    transitionTabBar(
      tabBarController,
      hidden: originalVisibility,
      animated: true
    )
    self.originalVisibility = nil
    managedTabBarController = nil
    appliedHiddenState = nil
  }

  private func applyTabBarVisibilityWhenAttached() {
    DispatchQueue.main.async { [weak self] in
      self?.applyTabBarVisibility()
    }
  }

  private func applyTabBarVisibility() {
    guard let tabBarController = findHostTabBarController() else {
      return
    }

    if managedTabBarController !== tabBarController {
      restoreTabBarVisibility()
      managedTabBarController = tabBarController
      originalVisibility = tabBarController.tabBar.isHidden
    }

    guard appliedHiddenState != shouldHideTabBar else {
      return
    }

    transitionTabBar(
      tabBarController,
      hidden: shouldHideTabBar,
      animated: originalVisibility == false || appliedHiddenState != nil
    )
    appliedHiddenState = shouldHideTabBar
  }

  private func transitionTabBar(
    _ tabBarController: UITabBarController,
    hidden: Bool,
    animated: Bool
  ) {
    let tabBar = tabBarController.tabBar
    tabBar.layer.removeAllAnimations()
    tabBar.isHidden = false

    if !hidden {
      tabBar.transform = CGAffineTransform(translationX: 0, y: max(tabBar.bounds.height, 1))
      tabBar.alpha = 0
    }
    let animations = {
      tabBar.transform = hidden
        ? CGAffineTransform(translationX: 0, y: max(tabBar.bounds.height, 1))
        : .identity
      tabBar.alpha = hidden ? 0 : 1
      tabBarController.view.layoutIfNeeded()
    }
    let completion: (Bool) -> Void = { _ in
      tabBar.isHidden = hidden
      if hidden {
        tabBar.transform = .identity
        tabBar.alpha = 1
      }
    }

    if animated {
      UIView.animate(
        withDuration: animationDuration,
        delay: 0,
        options: [.curveEaseInOut, .beginFromCurrentState],
        animations: animations,
        completion: completion
      )
    } else {
      animations()
      completion(true)
    }
  }

  private func findHostTabBarController() -> UITabBarController? {
    var current: UIViewController? = self
    while let controller = current {
      if let tabBarController = controller as? UITabBarController {
        return tabBarController
      }
      if let tabBarController = controller.tabBarController {
        return tabBarController
      }
      current = controller.parent
    }
    return nil
  }
}
#endif
