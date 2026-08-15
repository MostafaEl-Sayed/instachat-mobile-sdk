package pro.instakit.instachat.android

import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException

internal object MediaRetryDelays {
  val milliseconds = longArrayOf(500, 1_000, 2_000, 4_000, 8_000)

  fun isTransientStatus(statusCode: Int): Boolean =
    statusCode == 400 || statusCode == 404 || statusCode == 408 || statusCode == 425 ||
      statusCode == 429 || statusCode in 500..599

  fun isTransient(error: Throwable): Boolean = when (error) {
    is HttpDataSource.InvalidResponseCodeException -> isTransientStatus(error.responseCode)
    is SocketTimeoutException, is ConnectException -> true
    is IOException -> true
    else -> false
  }
}

internal class InstaChatLoadErrorHandlingPolicy : DefaultLoadErrorHandlingPolicy(MediaRetryDelays.milliseconds.size + 1) {
  override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
    if (!MediaRetryDelays.isTransient(loadErrorInfo.exception)) {
      return super.getRetryDelayMsFor(loadErrorInfo)
    }
    val index = loadErrorInfo.errorCount - 1
    return MediaRetryDelays.milliseconds.getOrNull(index) ?: TIME_UNSET
  }

  private companion object {
    const val TIME_UNSET = -9223372036854775807L
  }
}
