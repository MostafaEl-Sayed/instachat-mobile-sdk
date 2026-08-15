package pro.instakit.instachat.android

import android.content.Context
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.net.URI

internal data class PlaybackState(
  val messageId: String? = null,
  val isPlaying: Boolean = false,
  val isLoading: Boolean = false,
  val error: String? = null,
)

internal class MediaPlaybackController(
  private val context: Context,
  private val configuration: InstaChatConfiguration,
) {
  private val mediaCache = InstaChatMediaCache(context, configuration)
  private var player: ExoPlayer? = null
  private val _state = MutableStateFlow(PlaybackState())
  val state: StateFlow<PlaybackState> = _state.asStateFlow()

  fun toggle(message: InstaChatMessage) {
    if (_state.value.messageId == message.id && player != null) {
      if (player?.isPlaying == true) player?.pause() else player?.play()
      return
    }
    play(message)
  }

  fun play(message: InstaChatMessage) {
    play(message, preferRemote = false)
  }

  private fun play(message: InstaChatMessage, preferRemote: Boolean) {
    val attachment = message.attachment ?: return
    releasePlayer()
    val localUri = mediaCache.usableLocalUri(attachment.localUri)
    val uri = if (!preferRemote && localUri != null) localUri else Uri.parse(attachment.url)
    val canFallBackToRemote = !preferRemote && localUri != null && attachment.url != localUri.toString()
    val exoPlayer = ExoPlayer.Builder(context).build()
    player = exoPlayer
    exoPlayer.addListener(object : Player.Listener {
      override fun onPlaybackStateChanged(playbackState: Int) {
        _state.value = _state.value.copy(
          isLoading = playbackState == Player.STATE_BUFFERING,
          isPlaying = exoPlayer.isPlaying,
        )
      }

      override fun onIsPlayingChanged(isPlaying: Boolean) {
        _state.value = _state.value.copy(isPlaying = isPlaying, isLoading = false)
      }

      override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
        if (canFallBackToRemote && player === exoPlayer) {
          play(message, preferRemote = true)
          return
        }
        _state.value = _state.value.copy(
          isLoading = false,
          isPlaying = false,
          error = "Media is not available yet. Tap Retry to try again.",
        )
      }
    })
    val httpFactory = DefaultHttpDataSource.Factory().apply {
      setAllowCrossProtocolRedirects(true)
      if (shouldAuthorizeMedia(uri.toString(), configuration.baseUrl)) {
        setDefaultRequestProperties(mapOf("Authorization" to "Bearer ${configuration.token}"))
      }
    }
    val upstream = DefaultDataSource.Factory(context, httpFactory)
    val factory = if (uri.scheme?.startsWith("http") == true) {
      CacheDataSource.Factory()
        .setCache(InstaChatMediaPlaybackCache.get(context))
        .setUpstreamDataSourceFactory(upstream)
        .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
    } else {
      upstream
    }
    val mediaItem = MediaItem.Builder()
      .setUri(uri)
      .setMimeType(attachment.contentType)
      .build()
    val source = ProgressiveMediaSource.Factory(factory)
      .setLoadErrorHandlingPolicy(InstaChatLoadErrorHandlingPolicy())
      .createMediaSource(mediaItem)
    _state.value = PlaybackState(message.id, isLoading = true)
    exoPlayer.setMediaSource(source)
    exoPlayer.prepare()
    exoPlayer.playWhenReady = true
  }

  fun playerFor(messageId: String): Player? = player?.takeIf { _state.value.messageId == messageId }

  fun release() {
    releasePlayer()
    _state.value = PlaybackState()
  }

  fun stop(messageId: String) {
    if (_state.value.messageId == messageId) {
      release()
    }
  }

  private fun releasePlayer() {
    player?.release()
    player = null
  }
}

internal fun shouldAuthorizeMedia(mediaUrl: String, apiBaseUrl: String): Boolean = runCatching {
  val media = URI(mediaUrl)
  val api = URI(apiBaseUrl)
  val mediaPort = if (media.port >= 0) media.port else if (media.scheme == "https") 443 else 80
  val apiPort = if (api.port >= 0) api.port else if (api.scheme == "https") 443 else 80
  media.scheme.equals(api.scheme, true) && media.host.equals(api.host, true) && mediaPort == apiPort
}.getOrDefault(false)
