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
  @State private var mediaPreviewSelection: MediaPreviewSelection?
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
  var onProviderProfileTap: ((InstaChatRoom) -> Void)?

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
      ToolbarItem(placement: .principal) {
        providerTitle
      }

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
      store.setActiveRoom(room.id)
      guard !didLoad else {
        return
      }
      didLoad = true
      await store.loadMessages(roomID: room.id)
      if store.rooms.isEmpty {
        await store.loadRooms()
      }
    }
    .onDisappear {
      store.setActiveRoom(nil)
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
    .alert("Unable to Complete Action", isPresented: Binding(
      get: { store.errorMessage != nil },
      set: { isPresented in
        if !isPresented {
          store.dismissError()
        }
      }
    )) {
      Button("OK") {
        store.dismissError()
      }
    } message: {
      Text(store.errorMessage ?? "Please try again.")
    }
    .mediaPreviewCover(item: $mediaPreviewSelection) { selection in
      MediaPreviewScreen(
        selection: selection,
        mediaAuthorization: mediaAuthorization
      )
      .id(selection.id)
    }
  }

  private var providerTitle: some View {
    Button {
      onProviderProfileTap?(displayRoom)
    } label: {
      HStack(spacing: 8) {
        AvatarView(title: displayRoom.title, url: displayRoom.avatarURL, size: 30)

        Text(displayRoom.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(1)
      }
      .frame(maxWidth: 220)
    }
    .buttonStyle(.plain)
    .disabled(onProviderProfileTap == nil)
    .accessibilityLabel("Open provider profile")
  }

  private var displayRoom: InstaChatRoom {
    store.room(id: room.id) ?? room
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
              mediaAuthorization: mediaAuthorization,
              voicePlaybackController: voicePlaybackController,
              deliveryState: store.deliveryState(for: message.id),
              onRetry: {
                Task {
                  await store.retryMessage(messageID: message.id)
                }
              },
              onPreviewSelection: { selection in
                mediaPreviewSelection = selection
              }
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

  private var mediaAuthorization: MediaRequestAuthorization {
    MediaRequestAuthorization(
      apiBaseURL: store.configuration.baseURL,
      bearerToken: store.configuration.token
    )
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
    configuration.selection = .ordered
    configuration.preferredAssetRepresentationMode = .current
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
  var mediaAuthorization: MediaRequestAuthorization
  @ObservedObject var voicePlaybackController: VoiceNotePlaybackController
  var deliveryState: OutgoingMessageDeliveryState?
  var onRetry: () -> Void
  var onPreviewSelection: (MediaPreviewSelection) -> Void

  var body: some View {
    HStack(alignment: .bottom) {
      if isCurrentUser {
        Spacer(minLength: 60)
      }

      VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 5) {
        content

        deliveryFooter
      }

      if !isCurrentUser {
        Spacer(minLength: 60)
      }
    }
  }

  @ViewBuilder
  private var deliveryFooter: some View {
    VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 5) {
      HStack(spacing: 5) {
        Text(message.createdAt, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)

        if case .sending = deliveryState {
          ProgressView()
            .controlSize(.mini)
          Text("Sending")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      if case let .failed(failure) = deliveryState {
        Text(failure.message)
          .font(.caption2)
          .foregroundStyle(.red)
          .multilineTextAlignment(isCurrentUser ? .trailing : .leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 260, alignment: isCurrentUser ? .trailing : .leading)

        Button(action: onRetry) {
          Label("Retry", systemImage: "arrow.clockwise")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .foregroundStyle(.red)
            .background(Color.red.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry sending message")
        .accessibilityHint(failure.message)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch message.type {
    case .text:
      LinkedMessageText(messageID: message.id, content: message.content, isCurrentUser: isCurrentUser)
        .linkedBubbleStyle(isCurrentUser: isCurrentUser)
    case .location:
      LocationBubble(location: message.location, isCurrentUser: isCurrentUser)
    case .image, .file:
      if let attachment = message.attachment {
        AttachmentBubble(
          messageID: message.id,
          attachment: attachment,
          isCurrentUser: isCurrentUser,
          mediaAuthorization: mediaAuthorization,
          voicePlaybackController: voicePlaybackController,
          onPreview: onPreviewSelection
        )
      } else {
        LinkedMessageText(messageID: message.id, content: message.content, isCurrentUser: isCurrentUser)
          .linkedBubbleStyle(isCurrentUser: isCurrentUser)
      }
    }
  }
}

private struct LinkedMessageText: View {
  var messageID: String
  var content: String
  var isCurrentUser: Bool

  private var copyPayload: MessageCopyPayload {
    MessageCopyPayload(messageID: messageID, content: content)
  }

  var body: some View {
    Text(MessageLinkifier.attributedString(for: content, isCurrentUser: isCurrentUser))
      .fixedSize(horizontal: false, vertical: true)
      .environment(\.openURL, OpenURLAction { url in
        PlatformURLOpener.open(url)
        return .handled
      })
      .id(copyPayload)
      .contextMenu {
        Button {
          copyPayload.copy(using: PlatformPasteboard.copy)
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
      }
      .accessibilityLabel(content)
      .accessibilityAction(named: "Copy message") {
        copyPayload.copy(using: PlatformPasteboard.copy)
      }
  }
}

struct MessageCopyPayload: Hashable {
  var messageID: String
  var content: String

  func copy(using handler: (String) -> Void) {
    handler(content)
  }
}

enum MessageLinkifier {
  static func attributedString(for text: String, isCurrentUser: Bool) -> AttributedString {
    var attributed = AttributedString(text)
    attributed.foregroundColor = isCurrentUser ? .white : .primary

    for match in detectedURLMatches(in: text) {
      guard let range = Range(match.range, in: text),
            let attributedRange = Range(range, in: attributed),
            let url = match.url else {
        continue
      }

      attributed[attributedRange].link = url
      attributed[attributedRange].underlineStyle = .single
      attributed[attributedRange].foregroundColor = isCurrentUser ? .white : .accentColor
    }

    return attributed
  }

  static func detectedURLs(in text: String) -> [URL] {
    detectedURLMatches(in: text).compactMap(\.url)
  }

  private static func detectedURLMatches(in text: String) -> [NSTextCheckingResult] {
    guard !text.isEmpty else {
      return []
    }

    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return detector?
      .matches(in: text, options: [], range: range)
      .filter { result in
        guard let scheme = result.url?.scheme?.lowercased() else {
          return false
        }
        return scheme == "http" || scheme == "https"
      } ?? []
  }
}

enum PlatformURLOpener {
  static func open(_ url: URL) {
    #if os(iOS)
    UIApplication.shared.open(url)
    #elseif os(macOS)
    NSWorkspace.shared.open(url)
    #endif
  }
}

private struct AttachmentBubble: View {
  var messageID: String
  var attachment: InstaChatAttachment
  var isCurrentUser: Bool
  var mediaAuthorization: MediaRequestAuthorization
  @ObservedObject var voicePlaybackController: VoiceNotePlaybackController
  var onPreview: (MediaPreviewSelection) -> Void

  var body: some View {
    Group {
      if attachment.type == .image {
        imageBubble
          .bubbleStyle(isCurrentUser: isCurrentUser)
      } else if attachment.type == .video {
        Button {
          previewSelection.open(using: onPreview)
        } label: {
          fileBubble(systemImage: "play.rectangle.fill", title: attachment.fileName, subtitle: "Tap to preview")
            .bubbleStyle(isCurrentUser: isCurrentUser)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Play video \(attachment.fileName)")
      } else if attachment.type == .audio {
        VoiceNoteBubble(
          attachment: attachment,
          isCurrentUser: isCurrentUser,
          mediaAuthorization: mediaAuthorization,
          playbackController: voicePlaybackController
        )
          .bubbleStyle(isCurrentUser: isCurrentUser)
      } else {
        fileBubble(systemImage: "doc.fill", title: attachment.fileName, subtitle: attachment.contentType)
          .bubbleStyle(isCurrentUser: isCurrentUser)
      }
    }
  }

  private var imageBubble: some View {
    AuthenticatedRemoteImage(
      identity: mediaIdentity.id,
      url: attachment.url,
      fileName: attachment.fileName,
      authorization: mediaAuthorization,
      contentMode: .fill,
      previewSelection: previewSelection,
      onOpen: onPreview,
      openAccessibilityLabel: "Open image \(attachment.fileName)"
    )
    .frame(width: 220, height: 150)
    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .id(mediaIdentity)
  }

  private var mediaIdentity: MediaAttachmentIdentity {
    MediaAttachmentIdentity(messageID: messageID, attachment: attachment)
  }

  private var previewSelection: MediaPreviewSelection {
    MediaPreviewSelection(messageID: messageID, attachment: attachment)
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
  var mediaAuthorization: MediaRequestAuthorization
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
    if playbackError != nil {
      return "arrow.clockwise"
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
    if playbackError != nil {
      return "Retry voice note"
    }
    if isCached {
      return "Play voice note"
    }
    return "Download voice note"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Button {
        playbackController.toggle(attachment: attachment, authorization: mediaAuthorization)
      } label: {
        HStack(spacing: 10) {
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

          StaticWaveformView(seed: attachment.id)
            .frame(width: 150, height: 30)
            .foregroundStyle(isCurrentUser ? .white.opacity(0.86) : .secondary)

          Image(systemName: "waveform")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isCurrentUser ? .white.opacity(0.8) : .secondary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(playbackAccessibilityLabel)

      if playbackError != nil {
        HStack(spacing: 8) {
          Text("Voice note isn't ready yet.")
            .font(.caption2)
            .foregroundStyle(isCurrentUser ? .white.opacity(0.82) : .secondary)

          Button {
            playbackController.toggle(attachment: attachment, authorization: mediaAuthorization)
          } label: {
            Label("Retry", systemImage: "arrow.clockwise")
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 10)
              .frame(minHeight: 34)
              .background(
                isCurrentUser ? Color.white.opacity(0.16) : Color.accentColor.opacity(0.12),
                in: Capsule()
              )
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Retry voice note playback")
        }
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

  func toggle(attachment: InstaChatAttachment, authorization: MediaRequestAuthorization) {
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
          authorization: authorization,
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

  private func fail(attachmentID: String, error _: Error) {
    fail(attachmentID: attachmentID, message: "Voice note playback failed")
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
  var selection: MediaPreviewSelection
  var mediaAuthorization: MediaRequestAuthorization
  @Environment(\.dismiss) private var dismiss

  private var attachment: InstaChatAttachment {
    selection.attachment
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()
        if attachment.type == .image {
          AuthenticatedRemoteImage(
            identity: selection.id,
            url: attachment.url,
            fileName: attachment.fileName,
            authorization: mediaAuthorization,
            contentMode: .fit
          )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if attachment.type == .video {
          VideoPreviewPlayer(
            url: attachment.url,
            fileName: attachment.fileName,
            authorization: mediaAuthorization
          )
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
  var identity: String
  var url: URL
  var fileName: String?
  var authorization: MediaRequestAuthorization
  var contentMode: ContentMode
  var previewSelection: MediaPreviewSelection?
  var onOpen: ((MediaPreviewSelection) -> Void)?
  var openAccessibilityLabel: String?

  @State private var image: PlatformImage?
  @State private var didFail = false
  @State private var retryGeneration = 0

  init(
    identity: String,
    url: URL,
    fileName: String? = nil,
    authorization: MediaRequestAuthorization,
    contentMode: ContentMode,
    previewSelection: MediaPreviewSelection? = nil,
    onOpen: ((MediaPreviewSelection) -> Void)? = nil,
    openAccessibilityLabel: String? = nil
  ) {
    self.identity = identity
    self.url = url
    self.fileName = fileName
    self.authorization = authorization
    self.contentMode = contentMode
    self.previewSelection = previewSelection
    self.onOpen = onOpen
    self.openAccessibilityLabel = openAccessibilityLabel
    _image = State(initialValue: PlatformImageMemoryCache.shared.image(for: url, authorization: authorization))
  }

  var body: some View {
    GeometryReader { geometry in
      Group {
        if let image {
          loadedImage(image, size: geometry.size)
        } else if didFail {
          Rectangle()
            .fill(Color.gray.opacity(0.18))
            .overlay {
              VStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark")
                  .font(.system(size: 24, weight: .medium))
                  .foregroundStyle(.secondary)
                Button {
                  PlatformImageMemoryCache.shared.removeImage(for: url, authorization: authorization)
                  retryGeneration &+= 1
                } label: {
                  Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Attempts to load this image again")
              }
            }
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.18))
            .overlay {
              ProgressView()
            }
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .contentShape(Rectangle())
      .clipped()
    }
    .task(id: ImageLoadRequest(identity: identity, url: url, retryGeneration: retryGeneration)) {
      if let cachedImage = PlatformImageMemoryCache.shared.image(for: url, authorization: authorization) {
        image = cachedImage
        didFail = false
        return
      }
      image = nil
      didFail = false
      await loadImage(requestedURL: url)
    }
  }

  private func loadImage(requestedURL: URL) async {
    if requestedURL.isFileURL {
      let localURL = requestedURL
      let loadedImage = await Task.detached(priority: .utility) {
        SendablePlatformImage(PlatformImage(contentsOfFile: localURL.path))
      }.value
      guard !Task.isCancelled else {
        return
      }
      image = loadedImage.value
      didFail = loadedImage.value == nil
      if let loadedImage = loadedImage.value {
        PlatformImageMemoryCache.shared.store(loadedImage, for: requestedURL, authorization: authorization)
      }
      return
    }

    do {
      let data = try await AuthenticatedMediaDataLoader.load(
        remoteURL: requestedURL,
        fileName: fileName,
        authorization: authorization
      )
      let loadedImage = await Task.detached(priority: .utility) {
        SendablePlatformImage(PlatformImage(data: data))
      }.value
      guard !Task.isCancelled else {
        return
      }
      guard let loadedImage = loadedImage.value else {
        await AuthenticatedMediaCache.shared.removeCachedFile(for: requestedURL, fileName: fileName)
        didFail = true
        return
      }
      PlatformImageMemoryCache.shared.store(loadedImage, for: requestedURL, authorization: authorization)
      image = loadedImage
      didFail = false
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else {
        return
      }
      didFail = true
    }
  }

  @ViewBuilder
  private func loadedImage(_ image: PlatformImage, size: CGSize) -> some View {
    ZStack {
      platformImage(image)
        .resizable()
        .aspectRatio(contentMode: contentMode)
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)

      if let previewSelection, let onOpen {
        Button {
          previewSelection.open(using: onOpen)
        } label: {
          Color.clear
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .id(previewSelection.id)
        .accessibilityLabel(openAccessibilityLabel ?? "Open image")
      }
    }
    .frame(width: size.width, height: size.height)
    .contentShape(Rectangle())
    .clipped()
  }

  private func platformImage(_ image: PlatformImage) -> Image {
    #if os(iOS)
      Image(uiImage: image)
    #elseif os(macOS)
      Image(nsImage: image)
    #endif
  }
}

private struct ImageLoadRequest: Hashable {
  var identity: String
  var url: URL
  var retryGeneration: Int
}

#if os(iOS)
private typealias PlatformImage = UIImage
#elseif os(macOS)
private typealias PlatformImage = NSImage
#endif

private final class SendablePlatformImage: @unchecked Sendable {
  let value: PlatformImage?

  init(_ value: PlatformImage?) {
    self.value = value
  }
}

private final class PlatformImageMemoryCache: @unchecked Sendable {
  static let shared = PlatformImageMemoryCache()

  private let images = NSCache<NSString, PlatformImage>()

  private init() {
    images.countLimit = 120
    images.totalCostLimit = 128 * 1_024 * 1_024
  }

  func image(for url: URL, authorization: MediaRequestAuthorization) -> PlatformImage? {
    images.object(forKey: cacheKey(for: url, authorization: authorization))
  }

  func store(_ image: PlatformImage, for url: URL, authorization: MediaRequestAuthorization) {
    images.setObject(
      image,
      forKey: cacheKey(for: url, authorization: authorization),
      cost: estimatedMemoryCost(of: image)
    )
  }

  func removeImage(for url: URL, authorization: MediaRequestAuthorization) {
    images.removeObject(forKey: cacheKey(for: url, authorization: authorization))
  }

  private func cacheKey(for url: URL, authorization: MediaRequestAuthorization) -> NSString {
    "\(url.absoluteString)|\(authorization.cacheScope)" as NSString
  }

  private func estimatedMemoryCost(of image: PlatformImage) -> Int {
    #if os(iOS)
      let pixelWidth = image.size.width * image.scale
      let pixelHeight = image.size.height * image.scale
    #else
      let pixelWidth = image.size.width
      let pixelHeight = image.size.height
    #endif
    return max(1, Int(pixelWidth * pixelHeight * 4))
  }
}

private struct VideoPreviewPlayer: View {
  let url: URL
  let fileName: String
  let authorization: MediaRequestAuthorization
  @StateObject private var playbackController = VideoPreviewPlaybackController()

  var body: some View {
    ZStack {
      VideoPlayer(player: playbackController.player)

      if playbackController.isLoading {
        VStack(spacing: 12) {
          ProgressView()
            .tint(.white)
          Text("Preparing video...")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.82))
        }
      }

      if let playbackError = playbackController.playbackError {
        VStack(spacing: 14) {
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 28, weight: .semibold))
          Text(playbackError)
            .font(.footnote)
            .multilineTextAlignment(.center)
          Button {
            playbackController.load(
              url: url,
              fileName: fileName,
              authorization: authorization,
              force: true
            )
          } label: {
            Label("Retry", systemImage: "arrow.clockwise")
              .font(.subheadline.weight(.semibold))
              .padding(.horizontal, 18)
              .padding(.vertical, 10)
          }
          .buttonStyle(.borderedProminent)
          .accessibilityHint("Attempts to load and play this video again")
        }
        .foregroundStyle(.white)
        .padding(20)
      }
    }
      .task(id: VideoPlaybackRequest(url: url, fileName: fileName)) {
        playbackController.load(url: url, fileName: fileName, authorization: authorization)
      }
      .onDisappear {
        playbackController.stop()
      }
  }
}

private struct VideoPlaybackRequest: Hashable {
  var url: URL
  var fileName: String
}

@MainActor
private final class VideoPreviewPlaybackController: ObservableObject {
  @Published private(set) var player: AVPlayer?
  @Published private(set) var isLoading = true
  @Published private(set) var playbackError: String?

  private var activeRequest: VideoPlaybackRequest?
  private var loadTask: Task<Void, Never>?
  private var statusObservation: NSKeyValueObservation?

  deinit {
    loadTask?.cancel()
    statusObservation?.invalidate()
  }

  func load(
    url: URL,
    fileName: String,
    authorization: MediaRequestAuthorization,
    force: Bool = false
  ) {
    let request = VideoPlaybackRequest(url: url, fileName: fileName)
    guard force || request != activeRequest else {
      return
    }

    stop(resetRequest: false)
    activeRequest = request
    isLoading = true
    playbackError = nil

    loadTask = Task { [weak self] in
      do {
        let source = try await VideoPlaybackSourceResolver.resolve(
          remoteURL: url,
          fileName: fileName,
          authorization: authorization
        )
        try Task.checkCancellation()
        self?.installPlayer(source: source, request: request)
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else {
          return
        }
        self?.isLoading = false
        self?.playbackError = "Video is not available yet. Please try again."
      }
    }
  }

  func stop() {
    stop(resetRequest: true)
  }

  private func stop(resetRequest: Bool) {
    loadTask?.cancel()
    loadTask = nil
    statusObservation?.invalidate()
    statusObservation = nil
    player?.pause()
    player = nil
    if resetRequest {
      activeRequest = nil
    }
  }

  private func installPlayer(source: VideoPlaybackSource, request: VideoPlaybackRequest) {
    guard activeRequest == request else {
      return
    }

    let options: [String: Any]? = source.httpHeaders.isEmpty
      ? nil
      : ["AVURLAssetHTTPHeaderFieldsKey": source.httpHeaders]
    let asset = AVURLAsset(url: source.url, options: options)
    let item = AVPlayerItem(asset: asset)
    item.preferredForwardBufferDuration = 2
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    self.player = player

    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
      Task { @MainActor in
        guard let self, let item, self.player?.currentItem === item else {
          return
        }
        switch item.status {
        case .readyToPlay:
          self.isLoading = false
          self.playbackError = nil
        case .failed:
          self.player?.pause()
          self.isLoading = false
          self.playbackError = "Video playback failed. Please try again."
        case .unknown:
          break
        @unknown default:
          break
        }
      }
    }

    player.play()
  }
}

actor AuthenticatedMediaCache {
  static let shared = AuthenticatedMediaCache()

  private let cacheDirectory: URL
  private var inFlight: [URL: Task<URL, Error>] = [:]
  private var outgoingLocalFilesByName: [String: Set<URL>] = [:]

  init(cacheDirectory: URL? = nil) {
    #if DEBUG
    let overrideDirectory = ProcessInfo.processInfo.environment["INSTACHAT_MEDIA_CACHE_DIRECTORY"]
      .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    #else
    let overrideDirectory: URL? = nil
    #endif

    if let cacheDirectory {
      self.cacheDirectory = cacheDirectory
    } else if let overrideDirectory {
      self.cacheDirectory = overrideDirectory
    } else {
      let cachesDirectory = (try? FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )) ?? FileManager.default.temporaryDirectory
      self.cacheDirectory = cachesDirectory.appendingPathComponent("InstaChatMedia", isDirectory: true)
    }
  }

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

  func existingLocalFileURL(for remoteURL: URL, fileName: String? = nil) async -> URL? {
    if remoteURL.isFileURL {
      return remoteURL
    }

    if let destinationURL = try? cacheURL(for: remoteURL, fileName: fileName),
       FileManager.default.fileExists(atPath: destinationURL.path) {
      return destinationURL
    }

    guard let fileName else {
      return nil
    }

    let key = normalizedFileName(fileName)
    let existingAliases = Set((outgoingLocalFilesByName[key] ?? []).filter {
      FileManager.default.fileExists(atPath: $0.path)
    })
    outgoingLocalFilesByName[key] = existingAliases

    // A filename alone is not a safe media identity. When several selected
    // assets share a name, falling back to the last cached file can display
    // a different image than the message the user tapped.
    guard existingAliases.count == 1 else {
      return nil
    }
    return existingAliases.first
  }

  func removeCachedFile(for remoteURL: URL, fileName: String? = nil) async {
    guard !remoteURL.isFileURL,
          let destinationURL = try? cacheURL(for: remoteURL, fileName: fileName) else {
      return
    }
    try? FileManager.default.removeItem(at: destinationURL)
  }

  func storeLocalFile(at sourceURL: URL, for remoteURL: URL, fileName: String? = nil) async throws {
    guard sourceURL.isFileURL, !remoteURL.isFileURL else {
      return
    }

    let destinationURL = try cacheURL(for: remoteURL, fileName: fileName)
    let parentDirectory = destinationURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
    let stagedURL = parentDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(destinationURL.pathExtension)
    try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
    if FileManager.default.fileExists(atPath: destinationURL.path) {
      try FileManager.default.removeItem(at: destinationURL)
    }
    try FileManager.default.moveItem(at: stagedURL, to: destinationURL)
    registerOutgoingLocalFile(destinationURL, fileName: fileName ?? sourceURL.lastPathComponent)
  }

  func rekeyCachedFile(
    from sourceRemoteURL: URL,
    sourceFileName: String?,
    to destinationRemoteURL: URL,
    destinationFileName: String?
  ) async throws {
    guard sourceRemoteURL != destinationRemoteURL || sourceFileName != destinationFileName else {
      return
    }
    guard let sourceURL = await existingLocalFileURL(for: sourceRemoteURL, fileName: sourceFileName) else {
      return
    }
    try await storeLocalFile(
      at: sourceURL,
      for: destinationRemoteURL,
      fileName: destinationFileName ?? sourceFileName
    )
  }

  func localFileURL(
    for remoteURL: URL,
    authorization: MediaRequestAuthorization,
    fileName: String? = nil,
    session: URLSession = .shared,
    retryDelaysNanoseconds: [UInt64] = MediaRetryPolicy.defaultRetryDelaysNanoseconds
  ) async throws -> URL {
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
      let temporaryURL = try await Self.downloadWithRetry(
        remoteURL: remoteURL,
        authorization: authorization,
        session: session,
        retryDelaysNanoseconds: retryDelaysNanoseconds
      )

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

  private static func downloadWithRetry(
    remoteURL: URL,
    authorization: MediaRequestAuthorization,
    session: URLSession,
    retryDelaysNanoseconds: [UInt64]
  ) async throws -> URL {
    var latestError: Error = MediaDownloadError.unavailable

    for attempt in 0...retryDelaysNanoseconds.count {
      do {
        var request = URLRequest(url: remoteURL)
        authorization.headers(for: remoteURL).forEach {
          request.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        let (temporaryURL, response) = try await session.download(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
          throw MediaDownloadError.httpStatus(httpResponse.statusCode)
        }
        return temporaryURL
      } catch {
        latestError = error
        guard retryDelaysNanoseconds.indices.contains(attempt), MediaRetryPolicy.isTransient(error) else {
          throw error
        }
        try await Task.sleep(nanoseconds: retryDelaysNanoseconds[attempt])
      }
    }

    throw latestError
  }

  private func cacheURL(for remoteURL: URL, fileName: String?) throws -> URL {
    let extensionFromName = fileName.flatMap { URL(fileURLWithPath: $0).pathExtension.nilIfEmpty }
    let extensionFromURL = remoteURL.pathExtension.nilIfEmpty
    let fileExtension = extensionFromName ?? extensionFromURL ?? "bin"
    return cacheDirectory
      .appendingPathComponent(remoteURL.absoluteString.base64URLSafeString)
      .appendingPathExtension(fileExtension)
  }

  private func registerOutgoingLocalFile(_ localURL: URL, fileName: String?) {
    guard let fileName, !fileName.isEmpty else {
      return
    }
    outgoingLocalFilesByName[normalizedFileName(fileName), default: []].insert(localURL)
  }

  private func normalizedFileName(_ fileName: String) -> String {
    URL(fileURLWithPath: fileName).lastPathComponent.lowercased()
  }
}

enum MediaDownloadError: LocalizedError {
  case httpStatus(Int)
  case unavailable

  var errorDescription: String? {
    switch self {
    case let .httpStatus(statusCode):
      return "Media download failed (\(statusCode))."
    case .unavailable:
      return "Media is not available yet."
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
  func bubbleStyle(isCurrentUser: Bool) -> some View {
    padding(.horizontal, 13)
      .padding(.vertical, 9)
      .foregroundStyle(isCurrentUser ? .white : .primary)
      .background(isCurrentUser ? Color.accentColor : Color.gray.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  func linkedBubbleStyle(isCurrentUser: Bool) -> some View {
    padding(.horizontal, 13)
      .padding(.vertical, 9)
      .background(isCurrentUser ? Color.accentColor : Color.gray.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  @ViewBuilder
  func mediaPreviewCover<Item: Identifiable, Content: View>(
    item: Binding<Item?>,
    @ViewBuilder content: @escaping (Item) -> Content
  ) -> some View {
    #if os(iOS)
      fullScreenCover(item: item, content: content)
    #else
      sheet(item: item, content: content)
    #endif
  }
}

struct MediaPreviewSelection: Identifiable, Hashable {
  var messageID: String
  var attachment: InstaChatAttachment

  var id: String {
    identity.id
  }

  var identity: MediaAttachmentIdentity {
    MediaAttachmentIdentity(messageID: messageID, attachment: attachment)
  }

  func open(using handler: (MediaPreviewSelection) -> Void) {
    handler(self)
  }
}

struct MediaAttachmentIdentity: Identifiable, Hashable {
  var messageID: String
  var attachmentID: String
  var url: URL

  init(messageID: String, attachment: InstaChatAttachment) {
    self.messageID = messageID
    attachmentID = attachment.id
    url = attachment.url
  }

  var id: String {
    [messageID, attachmentID, url.absoluteString].joined(separator: "|")
  }
}
