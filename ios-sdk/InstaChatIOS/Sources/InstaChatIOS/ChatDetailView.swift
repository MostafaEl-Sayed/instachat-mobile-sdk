import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatDetailView: View {
  @EnvironmentObject private var store: InstaChatStore
  @State private var draft = ""
  @State private var didLoad = false
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var selectedVideo: PhotosPickerItem?
  var room: InstaChatRoom
  var onClose: (() -> Void)?

  var body: some View {
    VStack(spacing: 0) {
      transcript
      composer
    }
    .navigationTitle(room.title)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      if let onClose {
      #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
          SDKCloseButton(action: onClose)
        }
      #else
        ToolbarItem(placement: .automatic) {
          SDKCloseButton(action: onClose)
        }
      #endif
      }
    }
    .task {
      guard !didLoad else {
        return
      }
      didLoad = true
      await store.loadMessages(roomID: room.id)
    }
    .onChange(of: selectedPhoto) { item in
      handlePickedMedia(item)
    }
    .onChange(of: selectedVideo) { item in
      handlePickedMedia(item)
    }
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 10) {
          if store.isLoadingMessages && store.messages(for: room.id).isEmpty {
            ProgressView()
              .padding(.top, 24)
          }

          ForEach(store.messages(for: room.id)) { message in
            MessageBubbleView(message: message, isCurrentUser: message.senderID == store.configuration.user.id)
              .id(message.id)
          }

          if store.typingRoomIDs.contains(room.id) {
            TypingIndicatorView()
              .id("typing")
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
      }
      .background(Color.gray.opacity(0.08))
      .onChange(of: store.messages(for: room.id).count) { _ in
        scrollToBottom(proxy)
      }
      .onAppear {
        scrollToBottom(proxy, animated: false)
      }
    }
  }

  private var composer: some View {
    HStack(spacing: 10) {
      Menu {
        Button {
          Task {
            await store.sendLocation(InstaChatLocation(latitude: 37.7749, longitude: -122.4194, name: "Shared location"), roomID: room.id)
          }
        } label: {
          Label("Share Location", systemImage: "location")
        }

        PhotosPicker(selection: $selectedPhoto, matching: .images) {
          Label("Send Photo", systemImage: "photo")
        }

        PhotosPicker(selection: $selectedVideo, matching: .videos) {
          Label("Send Video", systemImage: "video")
        }
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 18, weight: .semibold))
          .frame(width: 38, height: 38)
          .background(Color.gray.opacity(0.14), in: Circle())
      }

      TextField("Message", text: $draft, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(1...5)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: draft) { value in
          store.sendTyping(roomID: room.id, isTyping: !value.isEmpty)
        }

      Button {
        let message = draft
        draft = ""
        Task {
          await store.sendText(message, roomID: room.id)
        }
      } label: {
        Image(systemName: "arrow.up")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.45) : Color.accentColor, in: Circle())
      }
      .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.regularMaterial)
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
    guard let lastID = store.messages(for: room.id).last?.id else {
      return
    }
    DispatchQueue.main.async {
      withAnimation(animated ? .easeOut(duration: 0.18) : nil) {
        proxy.scrollTo(lastID, anchor: .bottom)
      }
    }
  }

  private func handlePickedMedia(_ item: PhotosPickerItem?) {
    guard let item else {
      return
    }

    Task {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          return
        }
        let contentType = item.supportedContentTypes.first ?? .data
        let fileURL = FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString)
          .appendingPathExtension(contentType.preferredFilenameExtension ?? "dat")
        try data.write(to: fileURL, options: .atomic)
        await store.sendAttachment(fileURL: fileURL, roomID: room.id, contentType: contentType.preferredMIMEType)
      } catch {
        // The store owns visible backend errors. Picker read failures are intentionally ignored here.
      }
      selectedPhoto = nil
      selectedVideo = nil
    }
  }
}

private struct MessageBubbleView: View {
  var message: InstaChatMessage
  var isCurrentUser: Bool

  var body: some View {
    HStack(alignment: .bottom) {
      if isCurrentUser {
        Spacer(minLength: 60)
      }

      VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 5) {
        content

        Text(message.createdAt, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if !isCurrentUser {
        Spacer(minLength: 60)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch message.type {
    case .text:
      Text(message.content)
        .bubbleStyle(isCurrentUser: isCurrentUser)
    case .location:
      LocationBubble(location: message.location, isCurrentUser: isCurrentUser)
    case .image, .file:
      if let attachment = message.attachment {
        AttachmentBubble(attachment: attachment, isCurrentUser: isCurrentUser)
      } else {
        Text(message.content)
          .bubbleStyle(isCurrentUser: isCurrentUser)
      }
    }
  }
}

private struct AttachmentBubble: View {
  var attachment: InstaChatAttachment
  var isCurrentUser: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if attachment.type == .image {
        AsyncImage(url: attachment.url) { phase in
          switch phase {
          case let .success(image):
            image
              .resizable()
              .scaledToFill()
          default:
            Rectangle()
              .fill(Color.gray.opacity(0.18))
              .overlay {
                Image(systemName: "photo")
                  .foregroundStyle(.secondary)
              }
          }
        }
        .frame(width: 220, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      } else {
        Label(attachment.fileName, systemImage: attachment.type == .video ? "video" : "doc")
          .font(.subheadline)
      }
    }
    .bubbleStyle(isCurrentUser: isCurrentUser)
  }
}

private struct LocationBubble: View {
  var location: InstaChatLocation?
  var isCurrentUser: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.gray.opacity(0.18))
        .frame(width: 220, height: 110)
        .overlay {
          Image(systemName: "mappin.circle.fill")
            .font(.system(size: 36))
            .foregroundStyle(.red)
        }

      Text(location?.name ?? "Shared location")
        .font(.headline)

      if let location {
        Text("\(location.latitude, specifier: "%.5f"), \(location.longitude, specifier: "%.5f")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .bubbleStyle(isCurrentUser: isCurrentUser)
  }
}

private struct TypingIndicatorView: View {
  var body: some View {
    HStack {
      Text("Typing...")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.14), in: Capsule())
      Spacer()
    }
  }
}

private extension View {
  func bubbleStyle(isCurrentUser: Bool) -> some View {
    padding(.horizontal, 13)
      .padding(.vertical, 9)
      .foregroundStyle(isCurrentUser ? .white : .primary)
      .background(isCurrentUser ? Color.accentColor : Color.gray.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}
