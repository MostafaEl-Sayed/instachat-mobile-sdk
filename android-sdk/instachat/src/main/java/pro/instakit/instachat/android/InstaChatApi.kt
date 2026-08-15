package pro.instakit.instachat.android

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.annotations.SerializedName
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.BufferedSink
import okio.source
import java.io.IOException
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Base64
import java.util.concurrent.TimeUnit

internal class InstaChatApi(
  private val configuration: InstaChatConfiguration,
  private val contentResolver: ContentResolver,
  private val client: OkHttpClient = OkHttpClient.Builder()
    .connectTimeout(15, TimeUnit.SECONDS)
    .readTimeout(30, TimeUnit.SECONDS)
    .writeTimeout(60, TimeUnit.SECONDS)
    .build(),
) {
  private val gson = Gson()
  private val identity = TokenIdentity.from(configuration.token)
  private var socket: WebSocket? = null
  private var socketReady = CompletableDeferred<Unit>()
  private var closed = false
  private var eventHandler: ((RealtimeEvent) -> Unit)? = null

  suspend fun getRooms(): List<InstaChatRoom> = withContext(Dispatchers.IO) {
    val rooms: Array<BackendRoom> = get("/api/v1/me/rooms")
    rooms.map { it.toDomain(configuration.user.id, identity) }
      .sortedByDescending { it.updatedAt ?: Instant.EPOCH }
  }

  suspend fun getMessages(roomId: String, cursor: String? = null): InstaChatMessagesPage = withContext(Dispatchers.IO) {
    val query = buildString {
      append("?limit=").append(configuration.historyLimit)
      if (!cursor.isNullOrBlank()) append("&cursor=").append(java.net.URLEncoder.encode(cursor, "UTF-8"))
    }
    val page: BackendMessagesPage = get("/api/v1/rooms/$roomId/messages$query")
    InstaChatMessagesPage(
      page.data.filterNot { it.isDeleted == true }
        .map { it.toDomain(configuration.user.id, identity) }
        .sortedBy { it.createdAt },
      page.nextCursor,
    )
  }

  suspend fun upload(roomId: String, uri: Uri, contentType: String?): InstaChatAttachment = withContext(Dispatchers.IO) {
    val name = queryDisplayName(uri) ?: "attachment-${System.currentTimeMillis()}"
    val mime = contentType ?: contentResolver.getType(uri) ?: mimeFromName(name)
    val body = object : RequestBody() {
      override fun contentType() = mime.toMediaTypeOrNull()
      override fun contentLength(): Long = contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1
      override fun writeTo(sink: BufferedSink) {
        contentResolver.openInputStream(uri)?.use { sink.writeAll(it.source()) }
          ?: throw IOException("Selected file is no longer available.")
      }
    }
    val request = authorizedRequest("/api/v1/rooms/$roomId/attachments")
      .post(MultipartBody.Builder().setType(MultipartBody.FORM).addFormDataPart("file", name, body).build())
      .build()
    execute<BackendAttachment>(request).toDomain(uri)
  }

  fun observe(handler: (RealtimeEvent) -> Unit) {
    eventHandler = handler
    connect()
  }

  suspend fun sendText(roomId: String, text: String) = send(roomId, text, "text", emptyList())

  suspend fun sendLocation(roomId: String, location: InstaChatLocation) =
    send(roomId, gson.toJson(location), "location", emptyList())

  suspend fun sendAttachment(roomId: String, attachment: InstaChatAttachment) = send(
    roomId,
    attachment.fileName,
    if (attachment.type == InstaChatAttachmentType.IMAGE) "image" else "file",
    listOf(attachment.id),
  )

  suspend fun sendTyping(roomId: String, typing: Boolean) {
    sendEnvelope(if (typing) "typing.start" else "typing.stop", mapOf("room_id" to roomId))
  }

  fun disconnect() {
    closed = true
    eventHandler = null
    socket?.close(1000, "SDK closed")
    socket = null
  }

  private suspend fun send(roomId: String, content: String, type: String, attachmentIds: List<String>) {
    sendEnvelope("message.send", mapOf(
      "room_id" to roomId,
      "content" to content,
      "type" to type,
      "attachment_ids" to attachmentIds,
    ))
  }

  private suspend fun sendEnvelope(type: String, payload: Map<String, Any>) {
    var lastError: Throwable = IOException("Socket is not connected.")
    repeat(2) { attempt ->
      try {
        if (socket == null || !socketReady.isCompleted) connect()
        socketReady.await()
        if (socket?.send(gson.toJson(mapOf("type" to type, "payload" to payload))) != true) {
          throw IOException("Socket is not connected.")
        }
        return
      } catch (error: Throwable) {
        lastError = error
        socket?.cancel()
        socket = null
        socketReady = CompletableDeferred()
        if (attempt == 0) delay(300)
      }
    }
    throw lastError
  }

  @Synchronized
  private fun connect() {
    if (closed || socket != null) return
    socketReady = CompletableDeferred()
    val base = configuration.baseUrl.trimEnd('/')
      .replaceFirst("https://", "wss://")
      .replaceFirst("http://", "ws://")
    val request = Request.Builder()
      .url("$base/ws?token=${java.net.URLEncoder.encode(configuration.token, "UTF-8")}")
      .build()
    socket = client.newWebSocket(request, object : WebSocketListener() {
      override fun onOpen(webSocket: WebSocket, response: Response) {
        socketReady.complete(Unit)
      }

      override fun onMessage(webSocket: WebSocket, text: String) {
        text.lineSequence().filter { it.isNotBlank() }.forEach(::handleEvent)
      }

      override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        if (!socketReady.isCompleted) socketReady.completeExceptionally(t)
        socket = null
        if (!closed) eventHandler?.invoke(RealtimeEvent.ConnectionLost)
      }

      override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
        socket = null
      }
    })
  }

  private fun handleEvent(raw: String) {
    runCatching {
      val envelope = gson.fromJson(raw, JsonObject::class.java)
      val payload = envelope.getAsJsonObject("payload") ?: return
      when (envelope.get("type")?.asString) {
        "message.new" -> gson.fromJson(payload, BackendMessage::class.java)?.let {
          eventHandler?.invoke(RealtimeEvent.Message(it.toDomain(configuration.user.id, identity)))
        }
        "typing" -> eventHandler?.invoke(RealtimeEvent.Typing(
          payload.get("room_id")?.asString.orEmpty(),
          payload.get("user_id")?.asString,
          payload.get("is_typing")?.asBoolean == true,
        ))
      }
    }
  }

  private inline fun <reified T> get(path: String): T = execute(authorizedRequest(path).get().build())

  private fun authorizedRequest(path: String): Request.Builder = Request.Builder()
    .url(configuration.baseUrl.trimEnd('/') + if (path.startsWith('/')) path else "/$path")
    .header("Authorization", "Bearer ${configuration.token}")
    .header("Accept", "application/json")

  private inline fun <reified T> execute(request: Request): T = client.newCall(request).execute().use {
    val body = it.body?.string().orEmpty()
    if (!it.isSuccessful) throw IOException("Backend returned ${it.code}: $body")
    gson.fromJson(body, T::class.java)
  }

  private fun queryDisplayName(uri: Uri): String? {
    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
      if (cursor.moveToFirst()) return cursor.getString(0)
    }
    return uri.lastPathSegment
  }

  private fun mimeFromName(name: String): String = MimeTypeMap.getSingleton()
    .getMimeTypeFromExtension(name.substringAfterLast('.', "")) ?: "application/octet-stream"
}

internal sealed interface RealtimeEvent {
  data class Message(val message: InstaChatMessage) : RealtimeEvent
  data class Typing(val roomId: String, val userId: String?, val isTyping: Boolean) : RealtimeEvent
  data object ConnectionLost : RealtimeEvent
}

private data class TokenIdentity(val subject: String?, val externalUserId: String?) {
  companion object {
    fun from(token: String): TokenIdentity = runCatching {
      val payload = token.split('.')[1].replace('-', '+').replace('_', '/')
      val padded = payload.padEnd((payload.length + 3) / 4 * 4, '=')
      val json = Gson().fromJson(String(Base64.getDecoder().decode(padded)), JsonObject::class.java)
      TokenIdentity(json.get("sub")?.asString, json.get("ext_user_id")?.asString)
    }.getOrDefault(TokenIdentity(null, null))
  }
}

private data class BackendRoom(
  val id: String,
  @SerializedName("created_at") val createdAt: String? = null,
  @SerializedName("last_message") val lastMessage: BackendLastMessage? = null,
  @SerializedName("unread_count") val unreadCount: Int? = null,
  val members: List<BackendMember>? = null,
) {
  fun toDomain(currentUserId: String, identity: TokenIdentity): InstaChatRoom {
    val other = members?.firstOrNull { !it.matches(currentUserId, identity) } ?: members?.firstOrNull()
    return InstaChatRoom(
      id,
      other?.displayName ?: "Chat",
      lastMessage?.summary ?: if (other?.isOnline == true) "Online" else null,
      other?.avatarUrl,
      other?.externalUserId ?: other?.id,
      other?.profileUrl,
      parseInstant(lastMessage?.createdAt ?: createdAt),
      unreadCount ?: 0,
    )
  }
}

private data class BackendMember(
  val id: String,
  @SerializedName("ext_user_id") val externalUserId: String? = null,
  @SerializedName("display_name") val displayName: String,
  @SerializedName("avatar_url") val avatarUrl: String? = null,
  @SerializedName("profile_url") val profileUrl: String? = null,
  @SerializedName("is_online") val isOnline: Boolean? = null,
) {
  fun matches(currentUserId: String, identity: TokenIdentity) =
    id == currentUserId || id == identity.subject || externalUserId == currentUserId || externalUserId == identity.externalUserId
}

private data class BackendLastMessage(
  val id: String,
  val content: String,
  val type: String,
  @SerializedName("created_at") val createdAt: String,
  val attachments: List<BackendAttachment>? = null,
) {
  val summary: String get() = when (type) {
    "text" -> content.ifBlank { "Message" }
    "image" -> "Photo"
    "location" -> "Location"
    else -> when (attachments?.firstOrNull()?.resolvedType) {
      InstaChatAttachmentType.VIDEO -> "Video"
      InstaChatAttachmentType.AUDIO -> "Voice note"
      InstaChatAttachmentType.IMAGE -> "Photo"
      else -> "File"
    }
  }
}

private data class BackendMessagesPage(
  val data: List<BackendMessage>,
  @SerializedName("next_cursor") val nextCursor: String? = null,
)

private data class BackendMessage(
  val id: String,
  @SerializedName("room_id") val roomId: String,
  @SerializedName("sender_id") val senderId: String? = null,
  val content: String,
  val type: String,
  @SerializedName("is_deleted") val isDeleted: Boolean? = null,
  @SerializedName("created_at") val createdAt: String,
  val attachments: List<BackendAttachment>? = null,
  val sender: BackendSender? = null,
) {
  fun toDomain(currentUserId: String, identity: TokenIdentity): InstaChatMessage {
    val mine = senderId == currentUserId || senderId == identity.subject || senderId == identity.externalUserId
    val messageType = when (type) {
      "image" -> InstaChatMessageType.IMAGE
      "file" -> InstaChatMessageType.FILE
      "location" -> InstaChatMessageType.LOCATION
      else -> InstaChatMessageType.TEXT
    }
    return InstaChatMessage(
      id, roomId, if (mine) currentUserId else senderId ?: "provider", sender?.displayName,
      content, messageType, parseInstant(createdAt) ?: Instant.now(), attachments?.firstOrNull()?.toDomain(),
      if (messageType == InstaChatMessageType.LOCATION) runCatching { Gson().fromJson(content, InstaChatLocation::class.java) }.getOrNull() else null,
    )
  }
}

private data class BackendSender(@SerializedName("display_name") val displayName: String? = null)

private data class BackendAttachment(
  val id: String,
  @SerializedName("file_name") val fileName: String,
  @SerializedName("content_type") val contentType: String,
  val type: String? = null,
  @SerializedName("file_size") val fileSize: Long? = null,
  val url: String,
) {
  val resolvedType: InstaChatAttachmentType get() = when {
    type == "image" || contentType.startsWith("image/") -> InstaChatAttachmentType.IMAGE
    type == "video" || contentType.startsWith("video/") -> InstaChatAttachmentType.VIDEO
    type == "audio" || contentType.startsWith("audio/") -> InstaChatAttachmentType.AUDIO
    else -> InstaChatAttachmentType.FILE
  }

  fun toDomain(localUri: Uri? = null) = InstaChatAttachment(id, fileName, contentType, resolvedType, fileSize, url, localUri)
}

private fun parseInstant(value: String?): Instant? = value?.let { raw ->
  runCatching { Instant.parse(raw) }.getOrElse {
    runCatching { Instant.from(DateTimeFormatter.ISO_OFFSET_DATE_TIME.parse(raw)) }.getOrNull()
  }
}
