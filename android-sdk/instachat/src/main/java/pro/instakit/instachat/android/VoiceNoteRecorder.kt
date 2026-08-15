package pro.instakit.instachat.android

import android.content.Context
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File

internal data class RecordingState(
  val isRecording: Boolean = false,
  val elapsedMillis: Long = 0,
  val amplitudes: List<Float> = emptyList(),
  val error: String? = null,
)

internal class VoiceNoteRecorder(private val context: Context) {
  private val scope = CoroutineScope(Job() + Dispatchers.Main.immediate)
  private val _state = MutableStateFlow(RecordingState())
  val state: StateFlow<RecordingState> = _state.asStateFlow()
  private var recorder: MediaRecorder? = null
  private var output: File? = null
  private var meterJob: Job? = null
  private var startedAt = 0L

  fun start() {
    if (recorder != null) return
    runCatching {
      val file = File(context.cacheDir, "voice-${System.currentTimeMillis()}.m4a")
      @Suppress("DEPRECATION")
      val mediaRecorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()
      mediaRecorder.apply {
        setAudioSource(MediaRecorder.AudioSource.MIC)
        setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        setAudioEncodingBitRate(96_000)
        setAudioSamplingRate(44_100)
        setOutputFile(file.absolutePath)
        prepare()
        start()
      }
      output = file
      recorder = mediaRecorder
      startedAt = SystemClock.elapsedRealtime()
      _state.value = RecordingState(isRecording = true)
      meterJob = scope.launch {
        while (isActive && recorder != null) {
          val elapsed = SystemClock.elapsedRealtime() - startedAt
          val normalized = ((recorder?.maxAmplitude ?: 0) / 32767f).coerceIn(0.04f, 1f)
          _state.value = _state.value.copy(
            elapsedMillis = elapsed,
            amplitudes = (_state.value.amplitudes + normalized).takeLast(38),
          )
          delay(100)
        }
      }
    }.onFailure {
      cleanup(deleteFile = true)
      _state.value = RecordingState(error = "Voice recording could not start. Check microphone permission and try again.")
    }
  }

  fun finish(): Uri? {
    val file = output
    runCatching { recorder?.stop() }.onFailure { file?.delete() }
    cleanup(deleteFile = false)
    _state.value = RecordingState()
    return file?.takeIf { it.exists() && it.length() > 0 }?.let(Uri::fromFile)
  }

  fun cancel() {
    runCatching { recorder?.stop() }
    cleanup(deleteFile = true)
    _state.value = RecordingState()
  }

  private fun cleanup(deleteFile: Boolean) {
    meterJob?.cancel()
    meterJob = null
    runCatching { recorder?.release() }
    recorder = null
    if (deleteFile) output?.delete()
    output = null
  }
}
