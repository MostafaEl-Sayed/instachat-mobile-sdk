import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

struct ChatDetailView: View {
  @EnvironmentObject private var store: InstaChatStore
  @State private var draft = ""
  @State private var didLoad = false
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var selectedVideo: PhotosPickerItem?
  @State private var isAttachmentPanelVisible = false
  #if os(iOS)
  @StateObject private var voiceRecorder = VoiceNoteRecorder()
  #endif
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
    VStack(alignment: .leading, spacing: 8) {
      if isAttachmentPanelVisible {
        attachmentPanel
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }

      #if os(iOS)
      if voiceRecorder.isRecording {
        recordingComposer
      } else {
        standardComposer
      }
      #else
      standardComposer
      #endif
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.regularMaterial)
    .animation(.easeOut(duration: 0.18), value: isAttachmentPanelVisible)
  }

  private var standardComposer: some View {
    HStack(spacing: 10) {
      Button {
        isAttachmentPanelVisible.toggle()
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 18, weight: .semibold))
          .frame(width: 38, height: 38)
          .background(Color.gray.opacity(0.14), in: Circle())
      }
      .accessibilityLabel("Open attachments")

      #if os(iOS)
      Button {
        isAttachmentPanelVisible = false
        Task {
          do {
            try await voiceRecorder.start()
          } catch {
            store.reportError(error.localizedDescription)
          }
        }
      } label: {
        Image(systemName: "mic.fill")
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 38, height: 38)
          .background(Color.gray.opacity(0.14), in: Circle())
      }
      .accessibilityLabel("Record voice note")
      #endif

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
        sendDraft()
      } label: {
        Image(systemName: "arrow.up")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.45) : Color.accentColor, in: Circle())
      }
      .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private var attachmentPanel: some View {
    HStack(spacing: 10) {
      Button {
        isAttachmentPanelVisible = false
        Task {
          await store.sendLocation(InstaChatLocation(latitude: 37.7749, longitude: -122.4194, name: "Shared location"), roomID: room.id)
        }
      } label: {
        AttachmentPanelItem(title: "Location", systemImage: "location.fill")
      }

      PhotosPicker(selection: $selectedPhoto, matching: .images) {
        AttachmentPanelItem(title: "Photo", systemImage: "photo.fill")
      }

      PhotosPicker(selection: $selectedVideo, matching: .videos) {
        AttachmentPanelItem(title: "Video", systemImage: "video.fill")
      }
    }
    .padding(8)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  #if os(iOS)
  private var recordingComposer: some View {
    HStack(spacing: 12) {
      Button {
        voiceRecorder.cancel()
      } label: {
        Image(systemName: "trash")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 38, height: 38)
      }
      .accessibilityLabel("Cancel voice note")

      HStack(spacing: 10) {
        Circle()
          .fill(Color.red)
          .frame(width: 8, height: 8)
        Text(Self.voiceNoteDurationFormatter.string(from: voiceRecorder.elapsedSeconds) ?? "0:00")
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(minWidth: 42, alignment: .leading)
        LiveWaveformView(level: voiceRecorder.level)
          .frame(height: 28)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(Color.gray.opacity(0.14), in: Capsule())

      Button {
        do {
          let voiceNote = try voiceRecorder.finish()
          Task {
            await store.sendAttachment(fileURL: voiceNote.url, roomID: room.id, contentType: "audio/mp4")
          }
        } catch {
          store.reportError(error.localizedDescription)
        }
      } label: {
        Image(systemName: "arrow.up")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(Color.accentColor, in: Circle())
      }
      .accessibilityLabel("Send voice note")
    }
  }

  private static let voiceNoteDurationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    return formatter
  }()
  #endif

  private func sendDraft() {
    let message = draft
    draft = ""
    Task {
      await store.sendText(message, roomID: room.id)
    }
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
        isAttachmentPanelVisible = false
        guard let data = try await item.loadTransferable(type: Data.self) else {
          store.reportError("The selected media could not be loaded.")
          return
        }
        let contentType = item.supportedContentTypes.first ?? .data
        let fileURL = FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString)
          .appendingPathExtension(contentType.preferredFilenameExtension ?? "dat")
        try data.write(to: fileURL, options: .atomic)
        await store.sendAttachment(fileURL: fileURL, roomID: room.id, contentType: contentType.preferredMIMEType)
      } catch {
        store.reportError(error.localizedDescription)
      }
      selectedPhoto = nil
      selectedVideo = nil
    }
  }
}

private struct AttachmentPanelItem: View {
  var title: String
  var systemImage: String

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.primary)
      .padding(.horizontal, 11)
      .padding(.vertical, 9)
      .background(Color.gray.opacity(0.12), in: Capsule())
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
    Group {
      if attachment.type == .image {
        imageBubble
      } else if attachment.type == .audio {
        VoiceNoteBubble(attachment: attachment, isCurrentUser: isCurrentUser)
      } else if attachment.type == .video {
        fileBubble(systemImage: "play.rectangle.fill", title: attachment.fileName, subtitle: "Video")
      } else {
        fileBubble(systemImage: "doc.fill", title: attachment.fileName, subtitle: attachment.contentType)
      }
    }
    .bubbleStyle(isCurrentUser: isCurrentUser)
  }

  private var imageBubble: some View {
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
  }

  private func fileBubble(systemImage: String, title: String, subtitle: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 24))
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(isCurrentUser ? .white.opacity(0.75) : .secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: 240, alignment: .leading)
  }
}

private struct VoiceNoteBubble: View {
  var attachment: InstaChatAttachment
  var isCurrentUser: Bool

  @State private var player: AVPlayer?
  @State private var isPlaying = false
  @State private var endObserver: NSObjectProtocol?

  var body: some View {
    HStack(spacing: 10) {
      Button {
        togglePlayback()
      } label: {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(isCurrentUser ? Color.accentColor : .white)
          .frame(width: 34, height: 34)
          .background(isCurrentUser ? .white : Color.accentColor, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isPlaying ? "Pause voice note" : "Play voice note")

      StaticWaveformView(seed: attachment.id)
        .frame(width: 150, height: 30)
        .foregroundStyle(isCurrentUser ? .white.opacity(0.86) : .secondary)

      Image(systemName: "waveform")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(isCurrentUser ? .white.opacity(0.75) : .secondary)
    }
    .frame(maxWidth: 250, alignment: .leading)
    .onDisappear {
      player?.pause()
      player = nil
      isPlaying = false
      removeEndObserver()
    }
  }

  private func togglePlayback() {
    if isPlaying {
      player?.pause()
      isPlaying = false
      return
    }

    let player = player ?? AVPlayer(url: attachment.url)
    self.player = player
    player.play()
    isPlaying = true

    removeEndObserver()
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem,
      queue: .main
    ) { _ in
      isPlaying = false
      player.seek(to: .zero)
    }
  }

  private func removeEndObserver() {
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
  }
}

private struct LiveWaveformView: View {
  var level: Float

  var body: some View {
    HStack(alignment: .center, spacing: 3) {
      ForEach(0..<22, id: \.self) { index in
        Capsule()
          .frame(width: 3, height: barHeight(index: index))
          .opacity(0.55 + Double(level) * 0.35)
      }
    }
    .foregroundStyle(.secondary)
  }

  private func barHeight(index: Int) -> CGFloat {
    let phase = CGFloat(index % 7) / 6
    let baseline = 7 + sin(phase * .pi) * 9
    return baseline + CGFloat(level) * 20
  }
}

private struct StaticWaveformView: View {
  var seed: String

  var body: some View {
    HStack(alignment: .center, spacing: 3) {
      ForEach(0..<28, id: \.self) { index in
        Capsule()
          .frame(width: 3, height: barHeight(index: index))
      }
    }
  }

  private func barHeight(index: Int) -> CGFloat {
    let hash = abs(seed.hashValue + index * 31)
    return CGFloat(8 + hash % 22)
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
