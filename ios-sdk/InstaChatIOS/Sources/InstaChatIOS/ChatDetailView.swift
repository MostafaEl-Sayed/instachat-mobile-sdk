import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import AVKit
#if canImport(CoreLocation)
import CoreLocation
#endif
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
  @StateObject private var voicePlaybackController = VoiceNotePlaybackController()
  #if canImport(CoreLocation)
  @StateObject private var currentLocationProvider = CurrentLocationProvider()
  #endif
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
        onPick: { files in
          mediaPickerMode = nil
          handlePickedMediaFiles(files)
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
              mediaAuthToken: store.configuration.token,
              voicePlaybackController: voicePlaybackController
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
          await sendCurrentLocation()
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
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
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

  private func sendCurrentLocation() async {
    #if canImport(CoreLocation)
    do {
      let location = try await currentLocationProvider.currentLocation()
      await store.sendLocation(location, roomID: room.id)
    } catch {
      store.reportError(error.localizedDescription)
    }
    #else
    store.reportError("Location sharing is not available on this platform.")
    #endif
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
        let preparedFile = try await MediaPreflight.prepare(
          PickedMediaFile(url: fileURL, contentType: contentType.preferredMIMEType)
        )
        await store.sendAttachment(fileURL: preparedFile.url, roomID: room.id, contentType: preparedFile.contentType)
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
      do {
        let preparedFile = try await MediaPreflight.prepare(file)
        await store.sendAttachment(fileURL: preparedFile.url, roomID: room.id, contentType: preparedFile.contentType)
      } catch {
        store.reportError(error.localizedDescription)
      }
    }
  }

  private func handlePickedMediaFiles(_ files: [PickedMediaFile]) {
    isAttachmentPanelVisible = false
    Task {
      do {
        let preparedFiles = try await MediaPreflight.prepare(files)
        await store.sendAttachments(preparedFiles, roomID: room.id)
      } catch {
        store.reportError(error.localizedDescription)
      }
    }
  }
}

struct PickedMediaFile {
  var url: URL
  var contentType: String?
}

enum MediaPreflight {
  static let maxImageSelectionCount = 5
  static let maxVideoDuration: TimeInterval = 60
  static let compressVideoAboveBytes = 25 * 1024 * 1024
  static let maxVideoUploadBytes = 100 * 1024 * 1024

  static func prepare(_ files: [PickedMediaFile]) async throws -> [PickedMediaFile] {
    var preparedFiles: [PickedMediaFile] = []
    for file in files.prefix(maxImageSelectionCount) {
      preparedFiles.append(try await prepare(file))
    }
    return preparedFiles
  }

  static func prepare(_ file: PickedMediaFile) async throws -> PickedMediaFile {
    guard isVideo(file) else {
      return file
    }

    let asset = AVURLAsset(url: file.url)
    let duration = try await asset.load(.duration).seconds
    guard duration <= maxVideoDuration else {
      throw MediaPreflightError.videoTooLong(maxSeconds: Int(maxVideoDuration))
    }

    let fileSize = try file.url.fileSize
    guard fileSize <= maxVideoUploadBytes else {
      throw MediaPreflightError.videoTooLarge(maxMegabytes: maxVideoUploadBytes / 1_048_576)
    }

    guard fileSize > compressVideoAboveBytes else {
      return file
    }

    do {
      let compressedURL = try await compressVideo(file.url)
      let compressedSize = try compressedURL.fileSize
      guard compressedSize < fileSize else {
        return file
      }
      return PickedMediaFile(url: compressedURL, contentType: "video/mp4")
    } catch {
      return file
    }
  }

  private static func isVideo(_ file: PickedMediaFile) -> Bool {
    if let contentType = file.contentType, contentType.hasPrefix("video/") {
      return true
    }
    return UTType(filenameExtension: file.url.pathExtension)?.conforms(to: .movie) == true
  }

  private static func compressVideo(_ sourceURL: URL) async throws -> URL {
    let asset = AVURLAsset(url: sourceURL)
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
      throw MediaPreflightError.videoCompressionUnavailable
    }

    let destinationURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    exportSession.outputURL = destinationURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true
    let exportSessionBox = SendableExportSession(exportSession)

    return try await withCheckedThrowingContinuation { continuation in
      exportSession.exportAsynchronously {
        switch exportSessionBox.session.status {
        case .completed:
          continuation.resume(returning: destinationURL)
        case .failed, .cancelled:
          continuation.resume(throwing: exportSessionBox.session.error ?? MediaPreflightError.videoCompressionUnavailable)
        default:
          continuation.resume(throwing: MediaPreflightError.videoCompressionUnavailable)
        }
      }
    }
  }
}

private final class SendableExportSession: @unchecked Sendable {
  let session: AVAssetExportSession

  init(_ session: AVAssetExportSession) {
    self.session = session
  }
}

enum MediaPreflightError: LocalizedError {
  case videoTooLong(maxSeconds: Int)
  case videoTooLarge(maxMegabytes: Int)
  case videoCompressionUnavailable

  var errorDescription: String? {
    switch self {
    case let .videoTooLong(maxSeconds):
      return "Videos must be \(maxSeconds) seconds or shorter."
    case let .videoTooLarge(maxMegabytes):
      return "This video is too large. Choose a video smaller than \(maxMegabytes) MB."
    case .videoCompressionUnavailable:
      return "This video could not be prepared for upload."
    }
  }
}

extension URL {
  var fileSize: Int {
    get throws {
      let values = try resourceValues(forKeys: [.fileSizeKey])
      return values.fileSize ?? 0
    }
  }
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
  var onPick: ([PickedMediaFile]) -> Void
  var onCancel: () -> Void

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = mode.filter
    configuration.selectionLimit = mode == .photo ? MediaPreflight.maxImageSelectionCount : 1
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
    private let onPick: ([PickedMediaFile]) -> Void
    private let onCancel: () -> Void

    init(mode: MediaPickerMode, onPick: @escaping ([PickedMediaFile]) -> Void, onCancel: @escaping () -> Void) {
      self.mode = mode
      self.onPick = onPick
      self.onCancel = onCancel
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      guard !results.isEmpty else {
        onCancel()
        return
      }

      let limitedResults = Array(results.prefix(mode == .photo ? MediaPreflight.maxImageSelectionCount : 1))
      var pickedFiles = Array<PickedMediaFile?>(repeating: nil, count: limitedResults.count)
      let group = DispatchGroup()

      for (index, result) in limitedResults.enumerated() {
        group.enter()
        loadPickedFile(from: result.itemProvider) { file in
          pickedFiles[index] = file
          group.leave()
        }
      }

      group.notify(queue: .main) {
        let validFiles = pickedFiles.compactMap { $0 }
        if validFiles.isEmpty {
          self.onCancel()
        } else {
          self.onPick(validFiles)
        }
      }
    }

    private func loadPickedFile(from provider: NSItemProvider, completion: @escaping (PickedMediaFile?) -> Void) {
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
            assertionFailure(error.localizedDescription)
            completion(nil)
          }
          return
        }

        guard let url else {
          self.loadDataRepresentation(provider: provider, typeIdentifier: typeIdentifier, completion: completion)
          return
        }

        do {
          let copiedURL = try Self.copyTemporaryFile(from: url, typeIdentifier: typeIdentifier)
          DispatchQueue.main.async {
            completion(PickedMediaFile(url: copiedURL, contentType: UTType(typeIdentifier)?.preferredMIMEType))
          }
        } catch {
          self.loadDataRepresentation(provider: provider, typeIdentifier: typeIdentifier, completion: completion)
        }
      }
    }

    private func loadDataRepresentation(provider: NSItemProvider, typeIdentifier: String, completion: @escaping (PickedMediaFile?) -> Void) {
      provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
        guard let data else {
          DispatchQueue.main.async {
            completion(nil)
          }
          return
        }

        do {
          let fileURL = try Self.writeTemporaryData(data, typeIdentifier: typeIdentifier)
          DispatchQueue.main.async {
            completion(PickedMediaFile(url: fileURL, contentType: UTType(typeIdentifier)?.preferredMIMEType))
          }
        } catch {
          DispatchQueue.main.async {
            completion(nil)
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
  @ObservedObject var voicePlaybackController: VoiceNotePlaybackController

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
        AttachmentBubble(
          attachment: attachment,
          isCurrentUser: isCurrentUser,
          mediaAuthToken: mediaAuthToken,
          voicePlaybackController: voicePlaybackController
        )
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
  @ObservedObject var voicePlaybackController: VoiceNotePlaybackController

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
        VoiceNoteBubble(
          attachment: attachment,
          isCurrentUser: isCurrentUser,
          mediaAuthToken: mediaAuthToken,
          playbackController: voicePlaybackController
        )
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
  @ObservedObject var playbackController: VoiceNotePlaybackController

  private var isPlaying: Bool {
    playbackController.isPlaying(attachmentID: attachment.id)
  }

  private var isLoading: Bool {
    playbackController.isLoading(attachmentID: attachment.id)
  }

  private var isCached: Bool {
    playbackController.isCached(attachmentID: attachment.id)
  }

  private var playbackError: String? {
    playbackController.error(for: attachment.id)
  }

  private var playbackIconName: String {
    if isPlaying {
      return "pause.fill"
    }
    if isCached {
      return "play.fill"
    }
    return "arrow.down.circle.fill"
  }

  private var playbackAccessibilityLabel: String {
    if isLoading {
      return "Downloading voice note"
    }
    if isPlaying {
      return "Pause voice note"
    }
    if isCached {
      return "Play voice note"
    }
    return "Download voice note"
  }

  var body: some View {
    HStack(spacing: 10) {
      Button {
        playbackController.toggle(attachment: attachment, authToken: mediaAuthToken)
      } label: {
        ZStack {
          if isLoading {
            ProgressView()
              .controlSize(.small)
              .tint(isCurrentUser ? Color.accentColor : .white)
          } else {
            Image(systemName: playbackIconName)
              .font(.system(size: isCached || isPlaying ? 14 : 17, weight: .bold))
          }
        }
        .foregroundStyle(isCurrentUser ? Color.accentColor : .white)
        .frame(width: 34, height: 34)
        .background(isCurrentUser ? .white : Color.accentColor, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(playbackAccessibilityLabel)

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
    .task(id: attachment.id) {
      await playbackController.refreshCachedState(attachment: attachment)
    }
  }
}

@MainActor
private final class VoiceNotePlaybackController: ObservableObject {
  @Published private var playingAttachmentID: String?
  @Published private var loadingAttachmentID: String?
  @Published private var playbackErrors: [String: String] = [:]
  @Published private var cachedAttachmentIDs: Set<String> = []

  private var player: AVPlayer?
  private var activeAttachmentID: String?
  private var endObserver: NSObjectProtocol?
  private var statusObservation: NSKeyValueObservation?
  private var playbackTask: Task<Void, Never>?

  deinit {
    playbackTask?.cancel()
    player?.pause()
    statusObservation?.invalidate()
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
  }

  func isPlaying(attachmentID: String) -> Bool {
    playingAttachmentID == attachmentID
  }

  func isLoading(attachmentID: String) -> Bool {
    loadingAttachmentID == attachmentID
  }

  func isCached(attachmentID: String) -> Bool {
    cachedAttachmentIDs.contains(attachmentID)
  }

  func error(for attachmentID: String) -> String? {
    playbackErrors[attachmentID]
  }

  func refreshCachedState(attachment: InstaChatAttachment) async {
    guard !cachedAttachmentIDs.contains(attachment.id) else {
      return
    }

    let isCached = await AuthenticatedMediaCache.shared.cachedFileExists(
      for: attachment.url,
      fileName: attachment.fileName
    )
    if isCached {
      cachedAttachmentIDs.insert(attachment.id)
    }
  }

  func toggle(attachment: InstaChatAttachment, authToken: String) {
    if activeAttachmentID == attachment.id {
      stop()
      return
    }

    stop()
    activeAttachmentID = attachment.id
    loadingAttachmentID = attachment.id
    playbackErrors[attachment.id] = nil
    preparePlaybackSession(for: attachment.id)

    playbackTask = Task { [weak self] in
      do {
        let localURL = try await AuthenticatedMediaCache.shared.localFileURL(
          for: attachment.url,
          authToken: authToken,
          fileName: attachment.fileName
        )
        await MainActor.run {
          self?.cachedAttachmentIDs.insert(attachment.id)
          self?.startPlayback(from: localURL, attachmentID: attachment.id)
        }
      } catch {
        await MainActor.run {
          self?.fail(attachmentID: attachment.id, error: error)
        }
      }
    }
  }

  func stop() {
    playbackTask?.cancel()
    playbackTask = nil
    player?.pause()
    player = nil
    activeAttachmentID = nil
    playingAttachmentID = nil
    loadingAttachmentID = nil
    statusObservation?.invalidate()
    statusObservation = nil
    removeEndObserver()
  }

  private func startPlayback(from localURL: URL, attachmentID: String) {
    guard activeAttachmentID == attachmentID else {
      return
    }

    let player = AVPlayer(url: localURL)
    self.player = player

    statusObservation?.invalidate()
    statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { item, _ in
      DispatchQueue.main.async {
        switch item.status {
        case .readyToPlay:
          self.loadingAttachmentID = nil
        case .failed:
          self.fail(attachmentID: attachmentID, message: item.error?.localizedDescription ?? "Could not play audio")
        case .unknown:
          break
        @unknown default:
          break
        }
      }
    }

    player.play()
    playingAttachmentID = attachmentID

    removeEndObserver()
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem,
      queue: .main
    ) { _ in
      Task { @MainActor [weak self] in
        guard self?.activeAttachmentID == attachmentID else {
          return
        }
        self?.stop()
      }
    }
  }

  private func preparePlaybackSession(for attachmentID: String) {
    #if os(iOS)
      do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {
        playbackErrors[attachmentID] = error.localizedDescription
      }
    #endif
  }

  private func fail(attachmentID: String, error: Error) {
    fail(attachmentID: attachmentID, message: error.localizedDescription)
  }

  private func fail(attachmentID: String, message: String) {
    if activeAttachmentID == attachmentID {
      stop()
    }
    playbackErrors[attachmentID] = message
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
  @State private var isLoading = true
  @State private var playbackError: String?

  var body: some View {
    ZStack {
      VideoPlayer(player: player)

      if isLoading {
        ProgressView()
          .tint(.white)
      }

      if let playbackError {
        VStack(spacing: 10) {
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 28, weight: .semibold))
          Text(playbackError)
            .font(.footnote)
            .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(20)
      }
    }
      .task {
        guard player == nil else {
          return
        }
        do {
          let localURL = try await AuthenticatedMediaCache.shared.localFileURL(for: url, authToken: authToken)
          let player = AVPlayer(url: localURL)
          self.player = player
          isLoading = false
          player.play()
        } catch {
          isLoading = false
          playbackError = error.localizedDescription
        }
      }
      .onDisappear {
        player?.pause()
        player = nil
      }
  }
}

private actor AuthenticatedMediaCache {
  static let shared = AuthenticatedMediaCache()

  private var inFlight: [URL: Task<URL, Error>] = [:]

  func cachedFileExists(for remoteURL: URL, fileName: String? = nil) async -> Bool {
    if remoteURL.isFileURL {
      return true
    }

    do {
      let destinationURL = try cacheURL(for: remoteURL, fileName: fileName)
      return FileManager.default.fileExists(atPath: destinationURL.path)
    } catch {
      return false
    }
  }

  func localFileURL(for remoteURL: URL, authToken: String, fileName: String? = nil) async throws -> URL {
    if remoteURL.isFileURL {
      return remoteURL
    }

    let destinationURL = try cacheURL(for: remoteURL, fileName: fileName)
    if FileManager.default.fileExists(atPath: destinationURL.path) {
      return destinationURL
    }

    if let task = inFlight[remoteURL] {
      return try await task.value
    }

    let task = Task<URL, Error> {
      var request = URLRequest(url: remoteURL)
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
      let (temporaryURL, response) = try await URLSession.shared.download(for: request)

      if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
        throw MediaDownloadError.httpStatus(httpResponse.statusCode)
      }

      let parentDirectory = destinationURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
      }
      try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
      return destinationURL
    }

    inFlight[remoteURL] = task
    do {
      let localURL = try await task.value
      inFlight[remoteURL] = nil
      return localURL
    } catch {
      inFlight[remoteURL] = nil
      throw error
    }
  }

  private func cacheURL(for remoteURL: URL, fileName: String?) throws -> URL {
    let cacheDirectory = try FileManager.default.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    .appendingPathComponent("InstaChatMedia", isDirectory: true)

    let extensionFromName = fileName.flatMap { URL(fileURLWithPath: $0).pathExtension.nilIfEmpty }
    let extensionFromURL = remoteURL.pathExtension.nilIfEmpty
    let fileExtension = extensionFromName ?? extensionFromURL ?? "bin"
    return cacheDirectory
      .appendingPathComponent(remoteURL.absoluteString.base64URLSafeString)
      .appendingPathExtension(fileExtension)
  }
}

private enum MediaDownloadError: LocalizedError {
  case httpStatus(Int)

  var errorDescription: String? {
    switch self {
    case let .httpStatus(statusCode):
      return "Media download failed (\(statusCode))."
    }
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }

  var base64URLSafeString: String {
    Data(utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
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
