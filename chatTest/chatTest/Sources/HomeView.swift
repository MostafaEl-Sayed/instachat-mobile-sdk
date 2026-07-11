import InstaChatIOS
import SwiftUI

struct HomeView: View {
  @State private var baseURLText = ProcessInfo.processInfo.environment["INSTACHAT_BASE_URL"] ?? DemoCredentials.baseURL
  @State private var token = ProcessInfo.processInfo.environment["INSTACHAT_TOKEN"] ?? DemoCredentials.token
  @State private var roomIDText = ProcessInfo.processInfo.environment["INSTACHAT_ROOM_ID"] ?? ""
  @State private var initializedSDK: InstaChatSDK?
  @State private var activeChat: ActiveChatPresentation?
  @State private var shouldAutoOpenChat = ProcessInfo.processInfo.environment["INSTACHAT_AUTO_OPEN_CHAT"] == "1"
  @State private var validationMessage: String?

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Text("InstaChat SDK")
              .font(.largeTitle.bold())

            Text("Native SwiftUI host app for validating the iOS SDK integration.")
              .font(.body)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 8)
        }

        Section {
          TextField("Base URL", text: $baseURLText)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()

          SecureField("Token", text: $token)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("Connection")
        } footer: {
          Text("For production, inject the authenticated user token from the host app session.")
        }

        Section {
          Button {
            initializeSDK()
          } label: {
            HStack {
              Image(systemName: initializedSDK == nil ? "checkmark.seal" : "checkmark.seal.fill")
              Text(initializedSDK == nil ? "Initialize SDK" : "SDK Initialized")
              Spacer()
            }
            .font(.headline)
            .padding(.vertical, 4)
          }
        } footer: {
          Text("Initialize the SDK once with the authenticated token, then open either the chat list or a specific chat.")
        }

        Section {
          Button {
            openChatList()
          } label: {
            HStack {
              Image(systemName: "list.bullet")
              Text("Open Chat List")
              Spacer()
              Image(systemName: "arrow.up.right")
                .foregroundStyle(.secondary)
            }
            .font(.headline)
            .padding(.vertical, 4)
          }
          .disabled(initializedSDK == nil)

          TextField("Specific room ID", text: $roomIDText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

          Button {
            openSpecificChat()
          } label: {
            HStack {
              Image(systemName: "message.fill")
              Text("Open Specific Chat")
              Spacer()
              Image(systemName: "arrow.up.right")
                .foregroundStyle(.secondary)
            }
            .font(.headline)
            .padding(.vertical, 4)
          }
          .disabled(initializedSDK == nil || roomIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
          Text("Presentation")
        }

        Section {
          Text("""
          import InstaChatIOS

          let sdk = InstaChat.initialize(
            baseURL: URL(string: baseURL)!,
            token: token,
            user: InstaChatUser(id: "user-1", name: "Mostafa")
          )

          sdk.chatListView()
          sdk.chatView(roomID: "room-id", title: "Support")
          """)
          .font(.system(.footnote, design: .monospaced))
          .textSelection(.enabled)
        } header: {
          Text("Integration Code")
        }
      }
      .navigationTitle("chatTest")
      .alert("Check Configuration", isPresented: Binding(get: { validationMessage != nil }, set: { _ in validationMessage = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(validationMessage ?? "")
      }
      .fullScreenCover(item: $activeChat) { activeChat in
        ChatScreen(presentation: activeChat) {
          self.activeChat = nil
        }
      }
      .task {
        guard shouldAutoOpenChat else {
          return
        }
        shouldAutoOpenChat = false
        if let sdk = makeSDK() {
          initializedSDK = sdk
          activeChat = ActiveChatPresentation(sdk: sdk, mode: .list)
        }
      }
    }
  }

  private func makeSDK() -> InstaChatSDK? {
    guard let baseURL = URL(string: baseURLText), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }

    return InstaChat.initialize(
      baseURL: baseURL,
      token: token.trimmingCharacters(in: .whitespacesAndNewlines),
      user: InstaChatUser(id: DemoCredentials.userID, name: DemoCredentials.userName)
    )
  }

  private func initializeSDK() {
    guard let sdk = makeSDK() else {
      validationMessage = "Enter a valid base URL and token."
      return
    }

    initializedSDK = sdk
  }

  private func openChatList() {
    guard let initializedSDK else {
      validationMessage = "Initialize the SDK first."
      return
    }

    activeChat = ActiveChatPresentation(sdk: initializedSDK, mode: .list)
  }

  private func openSpecificChat() {
    guard let initializedSDK else {
      validationMessage = "Initialize the SDK first."
      return
    }

    let roomID = roomIDText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !roomID.isEmpty else {
      validationMessage = "Enter a room ID."
      return
    }

    activeChat = ActiveChatPresentation(sdk: initializedSDK, mode: .room(id: roomID, title: "Chat"))
  }
}

private struct ActiveChatPresentation: Identifiable {
  let id = UUID()
  let sdk: InstaChatSDK
  let mode: ChatPresentationMode
}

private enum ChatPresentationMode {
  case list
  case room(id: String, title: String)
}

private struct ChatScreen: View {
  let presentation: ActiveChatPresentation
  var onClose: () -> Void

  var body: some View {
    switch presentation.mode {
    case .list:
      presentation.sdk.chatListView(onClose: onClose)
    case let .room(id, title):
      presentation.sdk.chatView(roomID: id, title: title, onClose: onClose)
    }
  }
}

#Preview {
  HomeView()
}
