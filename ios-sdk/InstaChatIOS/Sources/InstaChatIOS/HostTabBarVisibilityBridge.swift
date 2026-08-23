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
  private weak var managedLayoutController: UIViewController?
  private var originalVisibility: Bool?
  private var originalAdditionalSafeAreaInsets: UIEdgeInsets?

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
    tabBarController.tabBar.isHidden = originalVisibility
    if let managedLayoutController,
       let originalAdditionalSafeAreaInsets {
      managedLayoutController.additionalSafeAreaInsets = originalAdditionalSafeAreaInsets
    }
    refreshLayout(for: tabBarController)
    self.originalVisibility = nil
    self.originalAdditionalSafeAreaInsets = nil
    managedLayoutController = nil
    managedTabBarController = nil
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
      managedLayoutController = tabBarController.selectedViewController
      originalAdditionalSafeAreaInsets = managedLayoutController?.additionalSafeAreaInsets
    }

    tabBarController.tabBar.isHidden = shouldHideTabBar
    if shouldHideTabBar {
      removeHiddenTabBarSafeArea(from: tabBarController)
    }
    refreshLayout(for: tabBarController)
  }

  private func removeHiddenTabBarSafeArea(from tabBarController: UITabBarController) {
    guard let managedLayoutController,
          let originalAdditionalSafeAreaInsets else {
      return
    }

    let deviceBottomInset = tabBarController.view.window?.safeAreaInsets.bottom ?? 0
    let tabBarContentHeight = max(0, tabBarController.tabBar.bounds.height - deviceBottomInset)
    var adjustedInsets = originalAdditionalSafeAreaInsets
    adjustedInsets.bottom -= tabBarContentHeight
    managedLayoutController.additionalSafeAreaInsets = adjustedInsets
  }

  private func refreshLayout(for tabBarController: UITabBarController) {
    tabBarController.view.setNeedsLayout()
    tabBarController.view.layoutIfNeeded()
    managedLayoutController?.view.setNeedsLayout()
    managedLayoutController?.view.layoutIfNeeded()
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
