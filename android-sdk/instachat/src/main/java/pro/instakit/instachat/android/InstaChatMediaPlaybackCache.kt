package pro.instakit.instachat.android

import android.content.Context
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

internal object InstaChatMediaPlaybackCache {
  private const val MAX_CACHE_BYTES = 250L * 1024 * 1024

  @Volatile
  private var cache: SimpleCache? = null

  fun get(context: Context): SimpleCache = cache ?: synchronized(this) {
    cache ?: SimpleCache(
      File(context.applicationContext.cacheDir, "instachat-playback"),
      LeastRecentlyUsedCacheEvictor(MAX_CACHE_BYTES),
      StandaloneDatabaseProvider(context.applicationContext),
    ).also { cache = it }
  }
}
