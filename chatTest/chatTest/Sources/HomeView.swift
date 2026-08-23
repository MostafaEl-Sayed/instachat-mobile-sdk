import InstaChatIOS
import SwiftUI

struct HomeView: View {
  @State private var baseURLText = ProcessInfo.processInfo.environment["INSTACHAT_BASE_URL"] ?? DemoCredentials.baseURL
  @State private var appBackendBaseURLText = ProcessInfo.processInfo.environment["GRANDIZAR_BACKEND_BASE_URL"] ?? DemoCredentials.appBackendBaseURL
  @State private var token = ProcessInfo.processInfo.environment["INSTACHAT_TOKEN"] ?? DemoCredentials.token
  @State private var googleMapsAPIKey = ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"] ?? ""
  @State private var providerIDText = ProcessInfo.processInfo.environment["GRANDIZAR_PROVIDER_ID"] ?? DemoCredentials.providerID
  @State private var roomIDText = ProcessInfo.processInfo.environment["INSTACHAT_ROOM_ID"] ?? ""
  @State private var initializedSDK: InstaChatSDK?
  @State private var activeChat: ActiveChatPresentation?
  @State private var shouldAutoOpenChat = ProcessInfo.processInfo.environment["INSTACHAT_AUTO_OPEN_CHAT"] == "1"
  @State private var validationMessage: String?
  @State private var providerProfileMessage: String?
  @State private var isStartingProviderChat = false

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

          SecureField("Google Maps API key (optional)", text: $googleMapsAPIKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("SDK Connection")
        } footer: {
          Text("This is the InstaChat backend used by the SDK after the host app has a room ID.")
        }

        Section {
          TextField("Grandizar backend base URL", text: $appBackendBaseURLText)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()

          TextField("Provider ID", text: $providerIDText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("Host App Backend")
        } footer: {
          Text("The host app calls its own backend to start a provider chat. That backend returns room_id, then the SDK opens the room.")
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

          Button {
            startProviderChat()
          } label: {
            HStack {
              Image(systemName: "person.crop.circle.badge.plus")
              Text(isStartingProviderChat ? "Starting Provider Chat..." : "Start Provider Chat")
              Spacer()
              if isStartingProviderChat {
                ProgressView()
              } else {
                Image(systemName: "arrow.up.right")
                  .foregroundStyle(.secondary)
              }
            }
            .font(.headline)
            .padding(.vertical, 4)
          }
          .disabled(
            initializedSDK == nil ||
              isStartingProviderChat ||
              appBackendBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
              providerIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
        } header: {
          Text("Presentation")
        }

        Section {
          Text("""
          import InstaChatIOS

          let sdk = InstaChat.initialize(
            baseURL: URL(string: baseURL)!,
            token: token,
            user: InstaChatUser(id: "user-1", name: "Mostafa"),
            googleMapsAPIKey: googleMapsAPIKey
          )

          let roomID = try await appBackend.startChat(providerID: "345", token: token)
          sdk.chatListView()
          sdk.chatView(roomID: roomID, title: "Support")
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
      .alert("Provider Profile", isPresented: Binding(get: { providerProfileMessage != nil }, set: { _ in providerProfileMessage = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(providerProfileMessage ?? "")
      }
      .fullScreenCover(item: $activeChat) { activeChat in
        ChatScreen(presentation: activeChat) {
          self.activeChat = nil
        } onProviderProfileTap: { room in
          providerProfileMessage = [
            "Provider: \(room.title)",
            "Internal id: \(room.providerID ?? "n/a")",
            "External id: \(room.providerExternalUserID ?? "n/a")",
            "Profile URL: \(room.providerProfileURL?.absoluteString ?? "n/a")"
          ].joined(separator: "\n")
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
      user: InstaChatUser(id: DemoCredentials.userID, name: DemoCredentials.userName),
      googleMapsAPIKey: googleMapsAPIKey
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

  private func startProviderChat() {
    guard let initializedSDK else {
      validationMessage = "Initialize the SDK first."
      return
    }

    let providerID = providerIDText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !providerID.isEmpty else {
      validationMessage = "Enter a provider ID."
      return
    }

    guard let appBackendBaseURL = URL(string: appBackendBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      validationMessage = "Enter the Grandizar backend base URL."
      return
    }

    isStartingProviderChat = true
    Task {
      do {
        let client = GrandizarStartChatClient(baseURL: appBackendBaseURL, token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        let startedChat = try await client.startChat(providerID: providerID)
        await MainActor.run {
          roomIDText = startedChat.roomID
          activeChat = ActiveChatPresentation(
            sdk: initializedSDK,
            mode: .room(id: startedChat.roomID, title: startedChat.title ?? "Chat")
          )
          isStartingProviderChat = false
        }
      } catch {
        await MainActor.run {
          validationMessage = error.localizedDescription
          isStartingProviderChat = false
        }
      }
    }
  }
}

private struct GrandizarStartedChat: Decodable {
  let roomID: String
  let title: String?

  enum CodingKeys: String, CodingKey {
    case roomID = "room_id"
    case roomId
    case id
    case title
    case name
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let roomID = try container.decodeIfPresent(String.self, forKey: .roomID) ??
      container.decodeIfPresent(String.self, forKey: .roomId) ??
      container.decodeIfPresent(String.self, forKey: .id) {
      self.roomID = roomID
    } else {
      throw DecodingError.keyNotFound(
        CodingKeys.roomID,
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected room_id in start-chat response.")
      )
    }
    title = try container.decodeIfPresent(String.self, forKey: .title) ??
      container.decodeIfPresent(String.self, forKey: .name)
  }
}

private struct GrandizarStartChatClient {
  let baseURL: URL
  let token: String

  func startChat(providerID: String) async throws -> GrandizarStartedChat {
    let url = baseURL.appending(path: "api/v1/user-app/chats/start")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(StartChatRequest(providerID: providerID))

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw StartChatError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw StartChatError.backendStatus(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
    }
    return try JSONDecoder().decode(GrandizarStartedChat.self, from: data)
  }
}

private struct StartChatRequest: Encodable {
  let providerID: String

  enum CodingKeys: String, CodingKey {
    case providerID = "provider_id"
  }
}

private enum StartChatError: LocalizedError {
  case invalidResponse
  case backendStatus(Int, String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "The Grandizar backend returned an invalid response."
    case let .backendStatus(status, body):
      return "The Grandizar backend returned \(status): \(body)"
    }
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
  var onProviderProfileTap: (InstaChatRoom) -> Void

  var body: some View {
    switch presentation.mode {
    case .list:
      presentation.sdk.chatListView(onClose: onClose, onProviderProfileTap: onProviderProfileTap)
    case let .room(id, title):
      presentation.sdk.chatView(roomID: id, title: title, onClose: onClose, onProviderProfileTap: onProviderProfileTap)
    }
  }
}

#Preview {
  HomeView()
}
