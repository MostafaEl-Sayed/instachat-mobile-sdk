package pro.instakit.instachat.android

import android.content.Context
import android.net.Uri
import com.google.gson.Gson
import java.io.File
import java.time.Instant

internal data class CachedChat(
  val rooms: List<InstaChatRoom>,
  val messagesByRoom: Map<String, List<InstaChatMessage>>,
)

internal class InstaChatCache(context: Context, configuration: InstaChatConfiguration) {
  private val gson = Gson()
  private val file = File(
    context.filesDir,
    "instachat-${(configuration.baseUrl + configuration.user.id + configuration.token.substringBefore('.')).hashCode()}.json",
  )

  fun read(): CachedChat? = runCatching {
    if (!file.exists()) return null
    gson.fromJson(file.readText(), CacheEnvelope::class.java).toDomain()
  }.getOrNull()

  fun write(state: InstaChatState) {
    runCatching {
      val envelope = CacheEnvelope(
        rooms = state.rooms.take(50).map(CacheRoom::from),
        messages = state.messagesByRoom.mapValues { (_, messages) -> messages.takeLast(100).map(CacheMessage::from) },
      )
      val temporary = File(file.parentFile, "${file.name}.tmp")
      temporary.writeText(gson.toJson(envelope))
      if (!temporary.renameTo(file)) {
        file.writeText(temporary.readText())
        temporary.delete()
      }
    }
  }
}

private data class CacheEnvelope(
  val rooms: List<CacheRoom> = emptyList(),
  val messages: Map<String, List<CacheMessage>> = emptyMap(),
) {
  fun toDomain() = CachedChat(rooms.map { it.toDomain() }, messages.mapValues { entry -> entry.value.map { it.toDomain() } })
}

private data class CacheRoom(
  val id: String,
  val title: String,
  val subtitle: String?,
  val avatarUrl: String?,
  val providerId: String?,
  val providerProfileUrl: String?,
  val updatedAt: String?,
  val unreadCount: Int,
) {
  fun toDomain() = InstaChatRoom(id, title, subtitle, avatarUrl, providerId, providerProfileUrl, parseInstant(updatedAt), unreadCount)
  companion object {
    fun from(room: InstaChatRoom) = CacheRoom(room.id, room.title, room.subtitle, room.avatarUrl, room.providerId, room.providerProfileUrl, room.updatedAt?.toString(), room.unreadCount)
  }
}

private data class CacheAttachment(
  val id: String,
  val fileName: String,
  val contentType: String,
  val type: String,
  val fileSize: Long?,
  val url: String,
  val localUri: String?,
) {
  fun toDomain() = InstaChatAttachment(id, fileName, contentType, enumValueOf(type), fileSize, url, localUri?.let(Uri::parse))
  companion object {
    fun from(value: InstaChatAttachment) = CacheAttachment(value.id, value.fileName, value.contentType, value.type.name, value.fileSize, value.url, value.localUri?.toString())
  }
}

private data class CacheLocation(val latitude: Double, val longitude: Double, val name: String?) {
  fun toDomain() = InstaChatLocation(latitude, longitude, name)
  companion object { fun from(value: InstaChatLocation) = CacheLocation(value.latitude, value.longitude, value.name) }
}

private data class CacheMessage(
  val id: String,
  val roomId: String,
  val senderId: String,
  val senderName: String?,
  val content: String,
  val type: String,
  val createdAt: String,
  val attachment: CacheAttachment?,
  val location: CacheLocation?,
  val deliveryState: String,
  val failureMessage: String?,
) {
  fun toDomain() = InstaChatMessage(
    id, roomId, senderId, senderName, content, enumValueOf(type),
    parseInstant(createdAt) ?: Instant.EPOCH, attachment?.toDomain(), location?.toDomain(),
    enumValueOf(deliveryState), failureMessage,
  )

  companion object {
    fun from(value: InstaChatMessage) = CacheMessage(
      value.id, value.roomId, value.senderId, value.senderName, value.content, value.type.name,
      value.createdAt.toString(), value.attachment?.let(CacheAttachment::from), value.location?.let(CacheLocation::from),
      value.deliveryState.name, value.failureMessage,
    )
  }
}

private fun parseInstant(value: String?): Instant? = value?.let { runCatching { Instant.parse(it) }.getOrNull() }
