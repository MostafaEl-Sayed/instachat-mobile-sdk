import SwiftUI
import UIKit

private enum ChatPresentationMode: String, CaseIterable, Identifiable {
  case bottomSheet
  case fullScreen

  var id: String { rawValue }

  var title: String {
    switch self {
    case .bottomSheet:
      return "Bottom Sheet"
    case .fullScreen:
      return "Full Screen"
    }
  }
}

struct ChatExampleHomeView: View {
  @State private var selectedMode: ChatPresentationMode = .bottomSheet
  @State private var presentedMode: ChatPresentationMode?
  @State private var isSheetExpanded = false

  var body: some View {
    NavigationView {
      ZStack(alignment: .bottomTrailing) {
        List {
          Section {
            VStack(alignment: .leading, spacing: 10) {
              Text("InstaChat SDK")
                .font(.largeTitle.weight(.bold))
              Text("SwiftUI host app embedding the reusable React Native chat SDK.")
                .font(.body)
                .foregroundStyle(.secondary)
            }
            .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
          }

          Section("Presentation") {
            Picker("Mode", selection: $selectedMode) {
              ForEach(ChatPresentationMode.allCases) { mode in
                Text(mode.title).tag(mode)
              }
            }
            .pickerStyle(.segmented)

            Button {
              openChat(selectedMode)
            } label: {
              Label("Open Selected Chat", systemImage: "message.fill")
            }

            Button {
              openChat(.bottomSheet)
            } label: {
              Label("Open Bottom Sheet", systemImage: "rectangle.bottomthird.inset.filled")
            }

            Button {
              openChat(.fullScreen)
            } label: {
              Label("Open Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
            }
          }

          Section("Backend") {
            InfoRow(title: "Base URL", value: ChatSDKNativeConfiguration.default.baseURL.absoluteString)
            InfoRow(title: "User", value: ChatSDKNativeConfiguration.default.userName)
          }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Chat SDK")
        .navigationViewStyle(.stack)

        Button {
          openChat(selectedMode)
        } label: {
          Image(systemName: "message.fill")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(Color.accentColor, in: Circle())
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        }
        .accessibilityLabel("Open chat")
        .padding(.trailing, 22)
        .padding(.bottom, 22)

        if presentedMode == .bottomSheet {
          BottomSheetOverlay(isExpanded: $isSheetExpanded, onClose: closeChat)
        }
      }
    }
    .fullScreenCover(
      isPresented: Binding(
        get: { presentedMode == .fullScreen },
        set: { isPresented in
          if !isPresented {
            closeChat()
          }
        }
      )
    ) {
      ChatFullScreenView(onClose: closeChat)
    }
  }

  private func openChat(_ mode: ChatPresentationMode) {
    presentedMode = mode
    isSheetExpanded = mode == .fullScreen
  }

  private func closeChat() {
    presentedMode = nil
    isSheetExpanded = false
  }
}

private struct BottomSheetOverlay: View {
  @Binding var isExpanded: Bool
  let onClose: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let sheetHeight = isExpanded ? proxy.size.height : min(proxy.size.height * 0.48, 430)

      ZStack(alignment: .bottom) {
        Color.black.opacity(isExpanded ? 0.12 : 0.06)
          .ignoresSafeArea()
          .onTapGesture(perform: onClose)

        ChatSheetView(isExpanded: $isExpanded, onClose: onClose)
          .frame(width: proxy.size.width, height: sheetHeight)
          .background(Color(.systemBackground))
          .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 24, style: .continuous))
          .shadow(color: .black.opacity(0.18), radius: 24, y: -6)
          .simultaneousGesture(
            TapGesture().onEnded {
              isExpanded = true
            }
          )
          .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isExpanded)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      .ignoresSafeArea(edges: .bottom)
      .ignoreHostKeyboardAvoidance()
    }
  }
}

private struct ChatSheetView: View {
  @Binding var isExpanded: Bool
  let onClose: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      ReactNativeChatView(configuration: .default)

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
          .background(Color(.secondarySystemBackground).opacity(0.95), in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Close chat")
      .padding(.top, isExpanded ? 13 : 13)
      .padding(.trailing, 14)
      .offset(y: -40)
    }
  }
}

private struct ChatFullScreenView: View {
  let onClose: () -> Void

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .topTrailing) {
        ReactNativeChatView(configuration: .default)
          .frame(height: proxy.size.height)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Color(.secondarySystemBackground).opacity(0.95), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close chat")
        .padding(.top, 55)
        .padding(.trailing, 14)
        .offset(y: -40)
      }
    }
    .ignoresSafeArea(edges: .bottom)
    .ignoreHostKeyboardAvoidance()
  }
}

private struct InfoRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }
}

#Preview {
  ChatExampleHomeView()
}

private final class KeyboardObserver: ObservableObject {
  @Published var height: CGFloat = 0
  @Published var animationDuration: Double = 0.25

  init() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardWillChangeFrame(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardWillHide(_:)),
      name: UIResponder.keyboardWillHideNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func keyboardWillChangeFrame(_ notification: Notification) {
    guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
      return
    }

    animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
    let screenHeight = UIScreen.main.bounds.height
    height = max(0, screenHeight - frame.minY)
  }

  @objc private func keyboardWillHide(_ notification: Notification) {
    animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
    height = 0
  }
}

private extension View {
  @ViewBuilder
  func ignoreHostKeyboardAvoidance() -> some View {
    if #available(iOS 14.0, *) {
      ignoresSafeArea(.keyboard, edges: .bottom)
    } else {
      self
    }
  }
}
