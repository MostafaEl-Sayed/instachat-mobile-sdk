import Foundation

#if os(iOS)
import AVFoundation

@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
  @Published private(set) var isRecording = false
  @Published private(set) var elapsedSeconds: TimeInterval = 0
  @Published private(set) var level: Float = 0

  private var recorder: AVAudioRecorder?
  private var recordingURL: URL?
  private var startedAt: Date?
  private var timer: Timer?

  func start() async throws {
    guard !isRecording else {
      return
    }

    let granted = await requestMicrophonePermission()
    guard granted else {
      throw VoiceNoteRecorderError.microphonePermissionDenied
    }

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
    try session.setActive(true)

    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instachat-voice-\(UUID().uuidString)")
      .appendingPathExtension("m4a")

    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 44_100,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
    recorder.delegate = self
    recorder.isMeteringEnabled = true
    recorder.prepareToRecord()
    recorder.record()

    self.recorder = recorder
    recordingURL = fileURL
    startedAt = Date()
    elapsedSeconds = 0
    level = 0
    isRecording = true
    startMeterTimer()
  }

  func finish() throws -> VoiceNoteFile {
    guard let recorder, let recordingURL, isRecording else {
      throw VoiceNoteRecorderError.noActiveRecording
    }

    let duration = max(elapsedSeconds, recorder.currentTime)
    recorder.stop()
    stopTimer()
    self.recorder = nil
    self.recordingURL = nil
    startedAt = nil
    elapsedSeconds = 0
    level = 0
    isRecording = false

    return VoiceNoteFile(url: recordingURL, duration: duration)
  }

  func cancel() {
    recorder?.stop()
    if let recordingURL {
      try? FileManager.default.removeItem(at: recordingURL)
    }
    stopTimer()
    recorder = nil
    recordingURL = nil
    startedAt = nil
    elapsedSeconds = 0
    level = 0
    isRecording = false
  }

  private func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
  }

  private func startMeterTimer() {
    stopTimer()
    timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, let recorder = self.recorder else {
          return
        }
        recorder.updateMeters()
        self.elapsedSeconds = Date().timeIntervalSince(self.startedAt ?? Date())
        let averagePower = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, (averagePower + 55) / 55))
        self.level = normalized
      }
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }
}

struct VoiceNoteFile {
  var url: URL
  var duration: TimeInterval
}

enum VoiceNoteRecorderError: LocalizedError {
  case microphonePermissionDenied
  case noActiveRecording

  var errorDescription: String? {
    switch self {
    case .microphonePermissionDenied:
      return "Microphone permission is required to record a voice note."
    case .noActiveRecording:
      return "No voice note is currently recording."
    }
  }
}
#endif
