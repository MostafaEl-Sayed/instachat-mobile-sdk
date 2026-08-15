package pro.instakit.instachat.android

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

internal data class LocalMediaInfo(
  val uri: Uri,
  val fileName: String,
  val contentType: String,
  val fileSize: Long,
)

internal class InstaChatMediaCache(
  private val context: Context,
  configuration: InstaChatConfiguration,
) {
  private val resolver = context.contentResolver
  private val directory = File(
    context.cacheDir,
    "instachat-media-${(configuration.baseUrl + configuration.user.id).hashCode()}",
  )

  suspend fun inspect(uri: Uri, contentTypeOverride: String? = null): LocalMediaInfo = withContext(Dispatchers.IO) {
    val fileName = displayName(uri) ?: "attachment-${System.currentTimeMillis()}"
    val contentType = contentTypeOverride
      ?: resolver.getType(uri)
      ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(fileName.substringAfterLast('.', "").lowercase())
      ?: "application/octet-stream"
    val size = resolver.openAssetFileDescriptor(uri, "r")?.use { it.length.coerceAtLeast(0) } ?: 0
    LocalMediaInfo(uri, fileName, contentType, size)
  }

  suspend fun preserve(source: LocalMediaInfo, messageId: String): LocalMediaInfo = withContext(Dispatchers.IO) {
    directory.mkdirs()
    val extension = source.fileName.substringAfterLast('.', "").takeIf { it.isNotBlank() }
    val destination = File(directory, buildString {
      append(messageId)
      if (extension != null) append('.').append(extension)
    })
    val temporary = File(directory, ".${UUID.randomUUID()}.tmp")
    resolver.openInputStream(source.uri)?.use { input ->
      temporary.outputStream().use(input::copyTo)
    } ?: error("Selected media is no longer available.")
    if (destination.exists()) destination.delete()
    if (!temporary.renameTo(destination)) {
      temporary.copyTo(destination, overwrite = true)
      temporary.delete()
    }
    prune()
    source.copy(uri = Uri.fromFile(destination), fileSize = destination.length())
  }

  fun usableLocalUri(uri: Uri?): Uri? {
    uri ?: return null
    if (uri.scheme != "file") return uri
    return uri.path?.let(::File)?.takeIf(File::isFile)?.let(Uri::fromFile)
  }

  private fun displayName(uri: Uri): String? = runCatching {
    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
      if (cursor.moveToFirst()) cursor.getString(0) else null
    }
  }.getOrNull() ?: uri.lastPathSegment?.substringAfterLast('/')

  private fun prune() {
    val files = directory.listFiles()?.filter(File::isFile)?.sortedByDescending(File::lastModified).orEmpty()
    var retainedBytes = 0L
    files.forEachIndexed { index, file ->
      retainedBytes += file.length()
      if (index >= MAX_FILES || retainedBytes > MAX_BYTES) file.delete()
    }
  }

  private companion object {
    const val MAX_FILES = 150
    const val MAX_BYTES = 300L * 1024 * 1024
  }
}
