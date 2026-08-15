package pro.instakit.instachat.android

import android.net.Uri
import java.time.Instant

data class InstaChatUser(
  val id: String,
  val name: String,
  val avatarUrl: String? = null,
)

data class InstaChatConfiguration(
  val baseUrl: String,
  val token: String,
  val user: InstaChatUser,
  val historyLimit: Int = 30,
  val title: String = "Messages",
)

data class InstaChatRoom(
  val id: String,
  val title: String,
  val subtitle: String? = null,
  val avatarUrl: String? = null,
  val providerId: String? = null,
  val providerProfileUrl: String? = null,
  val updatedAt: Instant? = null,
  val unreadCount: Int = 0,
)

enum class InstaChatMessageType { TEXT, IMAGE, FILE, LOCATION }
enum class InstaChatAttachmentType { IMAGE, VIDEO, AUDIO, FILE }
enum class InstaChatDeliveryState { SENDING, SENT, FAILED }

data class InstaChatAttachment(
  val id: String,
  val fileName: String,
  val contentType: String,
  val type: InstaChatAttachmentType,
  val fileSize: Long? = null,
  val url: String,
  val localUri: Uri? = null,
)

data class InstaChatLocation(
  val latitude: Double,
  val longitude: Double,
  val name: String? = null,
)

data class InstaChatMessage(
  val id: String,
  val roomId: String,
  val senderId: String,
  val senderName: String? = null,
  val content: String,
  val type: InstaChatMessageType,
  val createdAt: Instant,
  val attachment: InstaChatAttachment? = null,
  val location: InstaChatLocation? = null,
  val deliveryState: InstaChatDeliveryState = InstaChatDeliveryState.SENT,
  val failureMessage: String? = null,
) {
  val roomPreview: String
    get() = when (type) {
      InstaChatMessageType.TEXT -> content.ifBlank { "Message" }
      InstaChatMessageType.IMAGE -> "Photo"
      InstaChatMessageType.LOCATION -> "Location"
      InstaChatMessageType.FILE -> when (attachment?.type) {
        InstaChatAttachmentType.VIDEO -> "Video"
        InstaChatAttachmentType.AUDIO -> "Voice note"
        InstaChatAttachmentType.IMAGE -> "Photo"
        else -> "File"
      }
    }
}

internal data class InstaChatMessagesPage(
  val messages: List<InstaChatMessage>,
  val nextCursor: String?,
)

internal fun userFacingError(error: Throwable, media: InstaChatAttachmentType? = null): String {
  val prefix = when (media) {
    InstaChatAttachmentType.IMAGE -> "Photo"
    InstaChatAttachmentType.VIDEO -> "Video"
    InstaChatAttachmentType.AUDIO -> "Voice note"
    InstaChatAttachmentType.FILE -> "File"
    null -> "Message"
  }
  val message = error.message.orEmpty()
  return when {
    message.contains("401") || message.contains("403") -> "Your chat session has expired. Please reopen chat."
    message.contains("413") -> "$prefix is too large to send."
    message.contains("timeout", ignoreCase = true) -> "$prefix could not be sent because the connection timed out."
    else -> "$prefix could not be sent. Check your connection and tap Retry."
  }
}
