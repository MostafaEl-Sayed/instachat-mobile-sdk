import InstaChatIOS
import SwiftUI

struct HomeView: View {
  @State private var baseURLText = ProcessInfo.processInfo.environment["INSTACHAT_BASE_URL"] ?? DemoCredentials.baseURL
  @State private var token = ProcessInfo.processInfo.environment["INSTACHAT_TOKEN"] ?? DemoCredentials.token
  @State private var isShowingChat = ProcessInfo.processInfo.environment["INSTACHAT_AUTO_OPEN_CHAT"] == "1"
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
            openChat()
          } label: {
            HStack {
              Image(systemName: "message.fill")
              Text("Open Chat")
              Spacer()
              Image(systemName: "arrow.up.right")
                .foregroundStyle(.secondary)
            }
            .font(.headline)
            .padding(.vertical, 4)
          }
        }

        Section {
          Text("""
          import InstaChatIOS

          InstaChatView(
            configuration: InstaChatConfiguration(
              baseURL: URL(string: baseURL)!,
              token: token,
              user: InstaChatUser(id: "user-1", name: "Mostafa")
            )
          )
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
      .fullScreenCover(isPresented: $isShowingChat) {
        if let configuration {
          ChatScreen(configuration: configuration)
        }
      }
    }
  }

  private var configuration: InstaChatConfiguration? {
    guard let baseURL = URL(string: baseURLText), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }

    return InstaChatConfiguration(
      baseURL: baseURL,
      token: token.trimmingCharacters(in: .whitespacesAndNewlines),
      user: InstaChatUser(id: DemoCredentials.userID, name: DemoCredentials.userName)
    )
  }

  private func openChat() {
    guard configuration != nil else {
      validationMessage = "Enter a valid base URL and token."
      return
    }
    isShowingChat = true
  }
}

private struct ChatScreen: View {
  @Environment(\.dismiss) private var dismiss
  let configuration: InstaChatConfiguration

  var body: some View {
    NavigationStack {
      InstaChatView(configuration: configuration)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Close chat")
          }
        }
    }
  }
}

#Preview {
  HomeView()
}
