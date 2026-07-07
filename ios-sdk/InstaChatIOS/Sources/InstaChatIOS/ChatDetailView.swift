import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import AVKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ChatDetailView: View {
  @EnvironmentObject private var store: InstaChatStore
  @State private var draft = ""
  @State private var didLoad = false
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var selectedVideo: PhotosPickerItem?
  @State private var isAttachmentPanelVisible = false
  @State private var isPhotoPickerPresented = false
  @State private var isVideoPickerPresented = false
  #if os(iOS)
  @StateObject private var voiceRecorder = VoiceNoteRecorder()
  @State private var mediaPickerMode: MediaPickerMode?
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
    #if os(iOS)
    .sheet(item: $mediaPickerMode) { mode in
      MediaPickerSheet(
        mode: mode,
        onPick: { file in
          mediaPickerMode = nil
          handlePickedMediaFile(file)
        },
        onCancel: {
          mediaPickerMode = nil
        }
      )
    }
    #else
    .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
    .photosPicker(isPresented: $isVideoPickerPresented, selection: $selectedVideo, matching: .videos)
    #endif
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
            MessageBubbleView(
              message: message,
              isCurrentUser: message.senderID == store.configuration.user.id,
              mediaAuthToken: store.configuration.token
            )
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

      #if os(iOS)
        Button {
          mediaPickerMode = .photo
        } label: {
          AttachmentPanelItem(title: "Photo", systemImage: "photo.fill")
        }

        Button {
          mediaPickerMode = .video
        } label: {
          AttachmentPanelItem(title: "Video", systemImage: "video.fill")
        }
      #else
        Button {
          isPhotoPickerPresented = true
        } label: {
          AttachmentPanelItem(title: "Photo", systemImage: "photo.fill")
        }

        Button {
          isVideoPickerPresented = true
        } label: {
          AttachmentPanelItem(title: "Video", systemImage: "video.fill")
        }
      #endif
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

  private func handlePickedMediaFile(_ file: PickedMediaFile) {
    isAttachmentPanelVisible = false
    Task {
      await store.sendAttachment(fileURL: file.url, roomID: room.id, contentType: file.contentType)
    }
  }
}

private struct PickedMediaFile {
  var url: URL
  var contentType: String?
}

#if os(iOS)
private enum MediaPickerMode: String, Identifiable {
  case photo
  case video

  var id: String { rawValue }

  var filter: PHPickerFilter {
    switch self {
    case .photo:
      return .images
    case .video:
      return .videos
    }
  }
}

private struct MediaPickerSheet: UIViewControllerRepresentable {
  var mode: MediaPickerMode
  var onPick: (PickedMediaFile) -> Void
  var onCancel: () -> Void

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = mode.filter
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(mode: mode, onPick: onPick, onCancel: onCancel)
  }

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    private let mode: MediaPickerMode
    private let onPick: (PickedMediaFile) -> Void
    private let onCancel: () -> Void

    init(mode: MediaPickerMode, onPick: @escaping (PickedMediaFile) -> Void, onCancel: @escaping () -> Void) {
      self.mode = mode
      self.onPick = onPick
      self.onCancel = onCancel
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      picker.dismiss(animated: true)
      guard let provider = results.first?.itemProvider else {
        onCancel()
        return
      }

      let fallbackType = mode == .photo ? UTType.image.identifier : UTType.movie.identifier
      let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
        guard let type = UTType(identifier) else {
          return false
        }
        return mode == .photo ? type.conforms(to: .image) : type.conforms(to: .movie)
      } ?? fallbackType

      provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
        if let error {
          DispatchQueue.main.async {
            self.onCancel()
            assertionFailure(error.localizedDescription)
          }
          return
        }

        guard let url else {
          self.loadDataRepresentation(provider: provider, typeIdentifier: typeIdentifier)
          return
        }

        do {
          let copiedURL = try Self.copyTemporaryFile(from: url, typeIdentifier: typeIdentifier)
          DispatchQueue.main.async {
            self.onPick(PickedMediaFile(url: copiedURL, contentType: UTType(typeIdentifier)?.preferredMIMEType))
          }
        } catch {
          self.loadDataRepresentation(provider: provider, typeIdentifier: typeIdentifier)
        }
      }
    }

    private func loadDataRepresentation(provider: NSItemProvider, typeIdentifier: String) {
      provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
        guard let data else {
          DispatchQueue.main.async {
            self.onCancel()
          }
          return
        }

        do {
          let fileURL = try Self.writeTemporaryData(data, typeIdentifier: typeIdentifier)
          DispatchQueue.main.async {
            self.onPick(PickedMediaFile(url: fileURL, contentType: UTType(typeIdentifier)?.preferredMIMEType))
          }
        } catch {
          DispatchQueue.main.async {
            self.onCancel()
          }
        }
      }
    }

    private static func copyTemporaryFile(from sourceURL: URL, typeIdentifier: String) throws -> URL {
      let fileExtension = sourceURL.pathExtension.isEmpty ? (UTType(typeIdentifier)?.preferredFilenameExtension ?? "dat") : sourceURL.pathExtension
      let destinationURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(fileExtension)
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
      }
      try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
      return destinationURL
    }

    private static func writeTemporaryData(_ data: Data, typeIdentifier: String) throws -> URL {
      let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(UTType(typeIdentifier)?.preferredFilenameExtension ?? "dat")
      try data.write(to: fileURL, options: .atomic)
      return fileURL
    }
  }
}
#endif

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
  var mediaAuthToken: String

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
        AttachmentBubble(attachment: attachment, isCurrentUser: isCurrentUser, mediaAuthToken: mediaAuthToken)
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
  var mediaAuthToken: String

  @State private var isPreviewPresented = false

  var body: some View {
    Group {
      if attachment.type == .image {
        Button {
          isPreviewPresented = true
        } label: {
          imageBubble
            .bubbleStyle(isCurrentUser: isCurrentUser)
        }
        .buttonStyle(.plain)
      } else if attachment.type == .video {
        Button {
          isPreviewPresented = true
        } label: {
          fileBubble(systemImage: "play.rectangle.fill", title: attachment.fileName, subtitle: "Tap to preview")
            .bubbleStyle(isCurrentUser: isCurrentUser)
        }
        .buttonStyle(.plain)
      } else if attachment.type == .audio {
        VoiceNoteBubble(attachment: attachment, isCurrentUser: isCurrentUser, mediaAuthToken: mediaAuthToken)
          .bubbleStyle(isCurrentUser: isCurrentUser)
      } else {
        fileBubble(systemImage: "doc.fill", title: attachment.fileName, subtitle: attachment.contentType)
          .bubbleStyle(isCurrentUser: isCurrentUser)
      }
    }
    .mediaPreviewCover(isPresented: $isPreviewPresented) {
      MediaPreviewScreen(attachment: attachment, mediaAuthToken: mediaAuthToken)
    }
  }

  private var imageBubble: some View {
    AuthenticatedRemoteImage(url: attachment.url, authToken: mediaAuthToken, contentMode: .fill)
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
  var mediaAuthToken: String

  @State private var player: AVPlayer?
  @State private var isPlaying = false
  @State private var isLoading = false
  @State private var playbackError: String?
  @State private var endObserver: NSObjectProtocol?
  @State private var statusObservation: NSKeyValueObservation?

  var body: some View {
    HStack(spacing: 10) {
      Button {
        togglePlayback()
      } label: {
        Image(systemName: isLoading ? "hourglass" : (isPlaying ? "pause.fill" : "play.fill"))
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
    .overlay(alignment: .bottomLeading) {
      if let playbackError {
        Text(playbackError)
          .font(.caption2)
          .foregroundStyle(isCurrentUser ? .white.opacity(0.8) : .secondary)
          .offset(y: 18)
      }
    }
    .frame(maxWidth: 250, alignment: .leading)
    .onDisappear {
      player?.pause()
      player = nil
      isPlaying = false
      statusObservation?.invalidate()
      statusObservation = nil
      removeEndObserver()
    }
  }

  private func togglePlayback() {
    if isPlaying {
      player?.pause()
      isPlaying = false
      return
    }

    playbackError = nil
    preparePlaybackSession()
    let player = player ?? MediaPlayerFactory.player(for: attachment.url, authToken: mediaAuthToken)
    self.player = player
    isLoading = true

    statusObservation?.invalidate()
    statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { item, _ in
      DispatchQueue.main.async {
        switch item.status {
        case .readyToPlay:
          isLoading = false
        case .failed:
          isLoading = false
          isPlaying = false
          playbackError = item.error?.localizedDescription ?? "Could not play audio"
        case .unknown:
          break
        @unknown default:
          break
        }
      }
    }

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

  private func preparePlaybackSession() {
    #if os(iOS)
      do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {
        playbackError = error.localizedDescription
      }
    #endif
  }

  private func removeEndObserver() {
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
  }
}

private struct MediaPreviewScreen: View {
  var attachment: InstaChatAttachment
  var mediaAuthToken: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()
        if attachment.type == .image {
          AuthenticatedRemoteImage(url: attachment.url, authToken: mediaAuthToken, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if attachment.type == .video {
          VideoPreviewPlayer(url: attachment.url, authToken: mediaAuthToken)
            .ignoresSafeArea(edges: .bottom)
        } else {
          unavailablePreview(title: attachment.fileName, systemImage: "doc")
        }
      }
      .navigationTitle(attachment.fileName)
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Close preview")
        }
      }
    }
  }

  private func unavailablePreview(title: String, systemImage: String) -> some View {
    VStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 42))
      Text(title)
        .font(.headline)
    }
    .foregroundStyle(.white)
  }
}

private struct AuthenticatedRemoteImage: View {
  var url: URL
  var authToken: String
  var contentMode: ContentMode

  @State private var image: PlatformImage?
  @State private var didFail = false

  var body: some View {
    Group {
      if let image {
        platformImage(image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      } else if didFail {
        Rectangle()
          .fill(Color.gray.opacity(0.18))
          .overlay {
            Image(systemName: "photo")
              .foregroundStyle(.secondary)
          }
      } else {
        Rectangle()
          .fill(Color.gray.opacity(0.18))
          .overlay {
            ProgressView()
          }
      }
    }
    .clipped()
    .task(id: url) {
      await loadImage()
    }
  }

  private func loadImage() async {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

    do {
      let (data, _) = try await URLSession.shared.data(for: request)
      guard let loadedImage = PlatformImage(data: data) else {
        didFail = true
        return
      }
      image = loadedImage
      didFail = false
    } catch {
      didFail = true
    }
  }

  private func platformImage(_ image: PlatformImage) -> Image {
    #if os(iOS)
      Image(uiImage: image)
    #elseif os(macOS)
      Image(nsImage: image)
    #endif
  }
}

#if os(iOS)
private typealias PlatformImage = UIImage
#elseif os(macOS)
private typealias PlatformImage = NSImage
#endif

private struct VideoPreviewPlayer: View {
  let url: URL
  let authToken: String
  @State private var player: AVPlayer?

  var body: some View {
    VideoPlayer(player: player)
      .task {
        guard player == nil else {
          return
        }
        player = MediaPlayerFactory.player(for: url, authToken: authToken)
        player?.play()
      }
      .onDisappear {
        player?.pause()
        player = nil
      }
  }
}

private enum MediaPlayerFactory {
  static func player(for url: URL, authToken: String) -> AVPlayer {
    let asset = AVURLAsset(
      url: url,
      options: [
        "AVURLAssetHTTPHeaderFieldsKey": [
          "Authorization": "Bearer \(authToken)"
        ]
      ]
    )
    return AVPlayer(playerItem: AVPlayerItem(asset: asset))
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
  @Environment(\.openURL) private var openURL
  @State private var isActionDialogPresented = false

  var body: some View {
    Button {
      isActionDialogPresented = location != nil
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.gray.opacity(0.18))
          .frame(width: 220, height: 110)
          .overlay {
            Image(systemName: "mappin.circle.fill")
              .font(.system(size: 36))
              .foregroundStyle(.red)
          }

        HStack(spacing: 6) {
          Text(location?.name ?? "Shared location")
            .font(.headline)
          Image(systemName: "arrow.up.right.square")
            .font(.caption)
            .foregroundStyle(isCurrentUser ? .white.opacity(0.75) : .secondary)
        }

        if let location {
          Text("\(location.latitude, specifier: "%.5f"), \(location.longitude, specifier: "%.5f")")
            .font(.caption)
            .foregroundStyle(isCurrentUser ? .white.opacity(0.75) : .secondary)
        }
      }
      .bubbleStyle(isCurrentUser: isCurrentUser)
    }
    .buttonStyle(.plain)
    .confirmationDialog("Open Location", isPresented: $isActionDialogPresented, titleVisibility: .visible) {
      if let location {
        Button("Open in Apple Maps") {
          if let url = location.appleMapsURL {
            openURL(url)
          }
        }

        Button("Open in Google Maps") {
          if let url = location.googleMapsURL {
            openURL(url)
          }
        }

        Button("Copy Coordinates") {
          PlatformPasteboard.copy(location.coordinateText)
        }
      }

      Button("Cancel", role: .cancel) {}
    }
  }
}

private extension InstaChatLocation {
  var coordinateText: String {
    "\(latitude), \(longitude)"
  }

  var encodedName: String {
    (name ?? "Shared location").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Shared%20location"
  }

  var appleMapsURL: URL? {
    URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(encodedName)")
  }

  var googleMapsURL: URL? {
    URL(string: "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)")
  }
}

private enum PlatformPasteboard {
  static func copy(_ text: String) {
    #if os(iOS)
      UIPasteboard.general.string = text
    #elseif os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #endif
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
  @ViewBuilder
  func mediaPreviewCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
    #if os(iOS)
      fullScreenCover(isPresented: isPresented, content: content)
    #else
      sheet(isPresented: isPresented, content: content)
    #endif
  }

  func bubbleStyle(isCurrentUser: Bool) -> some View {
    padding(.horizontal, 13)
      .padding(.vertical, 9)
      .foregroundStyle(isCurrentUser ? .white : .primary)
      .background(isCurrentUser ? Color.accentColor : Color.gray.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}
