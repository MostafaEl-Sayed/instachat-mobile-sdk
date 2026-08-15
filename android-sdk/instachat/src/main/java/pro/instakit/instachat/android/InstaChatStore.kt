package pro.instakit.instachat.android

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Duration
import java.time.Instant
import java.util.UUID

internal data class InstaChatState(
  val rooms: List<InstaChatRoom> = emptyList(),
  val messagesByRoom: Map<String, List<InstaChatMessage>> = emptyMap(),
  val loadingRooms: Boolean = false,
  val loadingRoomIds: Set<String> = emptySet(),
  val typingRoomIds: Set<String> = emptySet(),
  val error: String? = null,
)

internal class InstaChatStore(
  val configuration: InstaChatConfiguration,
  context: Context,
) {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private val api = InstaChatApi(configuration, context.contentResolver)
  private val cache = InstaChatCache(context, configuration)
  private val appContext = context.applicationContext
  private val _state = MutableStateFlow(InstaChatState())
  val state: StateFlow<InstaChatState> = _state.asStateFlow()
  private val pending = mutableMapOf<String, PendingPayload>()
  private val cursors = mutableMapOf<String, String?>()
  private val loadingOlder = mutableSetOf<String>()
  private var activeRoomId: String? = null
  private var typingStopJob: Job? = null
  private var cacheWriteJob: Job? = null
  private val cacheReadJob: Job

  init {
    cacheReadJob = scope.launch {
      val cached = withContext(Dispatchers.IO) { cache.read() }
      if (cached != null) {
        update { it.copy(rooms = cached.rooms, messagesByRoom = cached.messagesByRoom) }
        restorePending(cached.messagesByRoom)
      }
    }
    api.observe(::onRealtime)
  }

  fun loadRooms() {
    if (_state.value.loadingRooms) return
    scope.launch {
      cacheReadJob.join()
      update { it.copy(loadingRooms = true, error = null) }
      runCatching { api.getRooms() }
        .onSuccess { fetched -> update { it.copy(rooms = mergeRooms(it.rooms, fetched), loadingRooms = false) } }
        .onFailure { error -> update { it.copy(loadingRooms = false, error = userFacingError(error)) } }
    }
  }

  fun openRoom(room: InstaChatRoom) {
    activeRoomId = room.id
    update { state ->
      val rooms = state.rooms.map { if (it.id == room.id) it.copy(unreadCount = 0) else it }
      state.copy(rooms = rooms)
    }
    if (_state.value.messagesByRoom[room.id].isNullOrEmpty()) loadMessages(room.id)
    else refreshMessages(room.id)
  }

  fun closeRoom() {
    activeRoomId = null
    typingStopJob?.cancel()
  }

  fun loadMessages(roomId: String) {
    if (roomId in _state.value.loadingRoomIds) return
    scope.launch {
      cacheReadJob.join()
      update { it.copy(loadingRoomIds = it.loadingRoomIds + roomId, error = null) }
      runCatching { api.getMessages(roomId) }
        .onSuccess { page ->
          cursors[roomId] = page.nextCursor
          mergeMessages(roomId, page.messages)
        }
        .onFailure { error -> update { it.copy(error = userFacingError(error)) } }
      update { it.copy(loadingRoomIds = it.loadingRoomIds - roomId) }
    }
  }

  private fun refreshMessages(roomId: String) {
    scope.launch {
      runCatching { api.getMessages(roomId) }.onSuccess { page ->
        cursors[roomId] = page.nextCursor
        mergeMessages(roomId, page.messages)
      }
    }
  }

  fun loadOlder(roomId: String) {
    val cursor = cursors[roomId] ?: return
    if (!loadingOlder.add(roomId)) return
    scope.launch {
      runCatching { api.getMessages(roomId, cursor) }.onSuccess { page ->
        cursors[roomId] = page.nextCursor
        mergeMessages(roomId, page.messages)
      }
      loadingOlder.remove(roomId)
    }
  }

  fun sendText(roomId: String, rawText: String) {
    val text = rawText.trim()
    if (text.isEmpty()) return
    val message = optimistic(roomId, text, InstaChatMessageType.TEXT)
    enqueue(message, PendingPayload.Text(text))
  }

  fun sendLocation(roomId: String, location: InstaChatLocation) {
    val message = optimistic(roomId, "Location", InstaChatMessageType.LOCATION).copy(location = location)
    enqueue(message, PendingPayload.Location(location))
  }

  fun sendMedia(roomId: String, uris: List<Uri>, contentType: String? = null) {
    uris.take(5).forEach { uri ->
      scope.launch {
        val mime = contentType ?: appContext.contentResolver.getType(uri) ?: "application/octet-stream"
        val type = attachmentType(mime)
        val validation = validateMedia(uri, type)
        if (validation != null) {
          update { it.copy(error = validation) }
          return@launch
        }
        val local = InstaChatAttachment(
          id = "local-attachment-${UUID.randomUUID()}",
          fileName = uri.lastPathSegment ?: "Attachment",
          contentType = mime,
          type = type,
          url = uri.toString(),
          localUri = uri,
        )
        val message = optimistic(
          roomId,
          local.fileName,
          if (type == InstaChatAttachmentType.IMAGE) InstaChatMessageType.IMAGE else InstaChatMessageType.FILE,
        ).copy(attachment = local)
        enqueue(message, PendingPayload.Media(uri, mime, null))
      }
    }
  }

  fun retry(messageId: String) {
    val payload = pending[messageId] ?: return
    updateMessage(messageId) { it.copy(deliveryState = InstaChatDeliveryState.SENDING, failureMessage = null) }
    scope.launch { performSend(messageId, payload) }
  }

  fun sendTyping(roomId: String) {
    typingStopJob?.cancel()
    scope.launch { runCatching { api.sendTyping(roomId, true) } }
    typingStopJob = scope.launch {
      delay(1_500)
      runCatching { api.sendTyping(roomId, false) }
    }
  }

  fun dismissError() = update { it.copy(error = null) }

  fun close() {
    typingStopJob?.cancel()
    api.disconnect()
    cacheWriteJob?.cancel()
    scope.coroutineContext[Job]?.cancel()
  }

  private fun enqueue(message: InstaChatMessage, payload: PendingPayload) {
    pending[message.id] = payload
    append(message)
    scope.launch { performSend(message.id, payload) }
  }

  private suspend fun performSend(messageId: String, payload: PendingPayload) {
    val message = findMessage(messageId) ?: return
    runCatching {
      when (payload) {
        is PendingPayload.Text -> api.sendText(message.roomId, payload.text)
        is PendingPayload.Location -> api.sendLocation(message.roomId, payload.location)
        is PendingPayload.Media -> {
          val attachment = payload.uploaded ?: api.upload(message.roomId, payload.uri, payload.contentType)
          pending[messageId] = payload.copy(uploaded = attachment)
          updateMessage(messageId) { local -> local.copy(attachment = attachment.copy(localUri = payload.uri)) }
          api.sendAttachment(message.roomId, attachment)
        }
      }
    }.onSuccess {
      updateMessage(messageId) { it.copy(deliveryState = InstaChatDeliveryState.SENT, failureMessage = null) }
    }.onFailure { error ->
      updateMessage(messageId) { it.copy(
        deliveryState = InstaChatDeliveryState.FAILED,
        failureMessage = userFacingError(error, it.attachment?.type),
      ) }
    }
  }

  private fun onRealtime(event: RealtimeEvent) {
    scope.launch {
      when (event) {
        is RealtimeEvent.Message -> upsertRealtime(event.message)
        is RealtimeEvent.Typing -> update { state ->
          state.copy(typingRoomIds = if (event.isTyping) state.typingRoomIds + event.roomId else state.typingRoomIds - event.roomId)
        }
        RealtimeEvent.ConnectionLost -> {
          delay(1_000)
          api.observe(::onRealtime)
        }
      }
    }
  }

  private fun upsertRealtime(incoming: InstaChatMessage) {
    val current = _state.value.messagesByRoom[incoming.roomId].orEmpty().toMutableList()
    val existing = current.indexOfFirst { it.id == incoming.id }
    if (existing >= 0) {
      current[existing] = incoming
    } else {
      val localIndex = current.indexOfLast { matchesLocalEcho(it, incoming, configuration.user.id) }
      if (localIndex >= 0) {
        val local = current[localIndex]
        pending.remove(local.id)
        current[localIndex] = incoming.copy(attachment = incoming.attachment?.copy(localUri = local.attachment?.localUri))
      } else {
        current += incoming
      }
    }
    setRoomMessages(incoming.roomId, current)
    updateRoomPreview(incoming, incrementUnread = incoming.senderId != configuration.user.id && activeRoomId != incoming.roomId)
  }

  private fun mergeMessages(roomId: String, fetched: List<InstaChatMessage>) {
    val merged = _state.value.messagesByRoom[roomId].orEmpty().toMutableList()
    fetched.forEach { incoming ->
      val index = merged.indexOfFirst { it.id == incoming.id }
      if (index >= 0) merged[index] = incoming
      else {
        val localIndex = merged.indexOfLast { matchesLocalEcho(it, incoming, configuration.user.id) }
        if (localIndex >= 0) {
          val local = merged[localIndex]
          pending.remove(local.id)
          merged[localIndex] = incoming.copy(attachment = incoming.attachment?.copy(localUri = local.attachment?.localUri))
        } else merged += incoming
      }
    }
    setRoomMessages(roomId, merged)
  }

  private fun append(message: InstaChatMessage) {
    val messages = _state.value.messagesByRoom[message.roomId].orEmpty() + message
    setRoomMessages(message.roomId, messages)
    updateRoomPreview(message, false)
  }

  private fun setRoomMessages(roomId: String, messages: List<InstaChatMessage>) {
    update { it.copy(messagesByRoom = it.messagesByRoom + (roomId to messages.distinctBy { message -> message.id }.sortedBy { message -> message.createdAt })) }
    scheduleCacheWrite()
  }

  private fun updateRoomPreview(message: InstaChatMessage, incrementUnread: Boolean) {
    update { state ->
      val old = state.rooms.firstOrNull { it.id == message.roomId }
        ?: InstaChatRoom(message.roomId, message.senderName ?: "Chat")
      val updated = old.copy(
        subtitle = message.roomPreview,
        updatedAt = message.createdAt,
        unreadCount = if (incrementUnread) old.unreadCount + 1 else old.unreadCount,
      )
      state.copy(rooms = listOf(updated) + state.rooms.filterNot { it.id == updated.id })
    }
    scheduleCacheWrite()
  }

  private fun mergeRooms(local: List<InstaChatRoom>, remote: List<InstaChatRoom>): List<InstaChatRoom> {
    val localById = local.associateBy { it.id }
    return remote.map { room ->
      val cached = localById[room.id]
      if (cached?.updatedAt != null && (room.updatedAt == null || cached.updatedAt > room.updatedAt)) {
        room.copy(subtitle = cached.subtitle, updatedAt = cached.updatedAt, unreadCount = maxOf(room.unreadCount, cached.unreadCount))
      } else room
    }.sortedByDescending { it.updatedAt ?: Instant.EPOCH }
  }

  private fun updateMessage(messageId: String, transform: (InstaChatMessage) -> InstaChatMessage) {
    val state = _state.value
    state.messagesByRoom.forEach { (roomId, messages) ->
      val index = messages.indexOfFirst { it.id == messageId }
      if (index >= 0) {
        val updated = messages.toMutableList().also { it[index] = transform(it[index]) }
        setRoomMessages(roomId, updated)
        updateRoomPreview(updated[index], false)
        return
      }
    }
  }

  private fun findMessage(id: String): InstaChatMessage? = _state.value.messagesByRoom.values.flatten().firstOrNull { it.id == id }

  private fun optimistic(roomId: String, content: String, type: InstaChatMessageType) = InstaChatMessage(
    id = "local-${UUID.randomUUID()}", roomId = roomId, senderId = configuration.user.id,
    senderName = configuration.user.name, content = content, type = type, createdAt = Instant.now(),
    deliveryState = InstaChatDeliveryState.SENDING,
  )

  private fun validateMedia(uri: Uri, type: InstaChatAttachmentType): String? {
    val size = appContext.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: 0
    if (size > 100L * 1024 * 1024) return "This file is larger than the 100 MB upload limit."
    if (type == InstaChatAttachmentType.VIDEO) {
      val durationMs = runCatching {
        MediaMetadataRetriever().use { retriever ->
          retriever.setDataSource(appContext, uri)
          retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
        }
      }.getOrDefault(0)
      if (durationMs > 60_000) return "Videos must be one minute or shorter."
    }
    return null
  }

  private fun attachmentType(mime: String) = when {
    mime.startsWith("image/") -> InstaChatAttachmentType.IMAGE
    mime.startsWith("video/") -> InstaChatAttachmentType.VIDEO
    mime.startsWith("audio/") -> InstaChatAttachmentType.AUDIO
    else -> InstaChatAttachmentType.FILE
  }

  private fun update(transform: (InstaChatState) -> InstaChatState) {
    _state.value = transform(_state.value)
  }

  private fun scheduleCacheWrite() {
    cacheWriteJob?.cancel()
    cacheWriteJob = scope.launch {
      delay(250)
      val snapshot = _state.value
      withContext(Dispatchers.IO) { cache.write(snapshot) }
    }
  }

  private fun restorePending(messagesByRoom: Map<String, List<InstaChatMessage>>) {
    messagesByRoom.values.flatten()
      .filter { it.id.startsWith("local-") && it.deliveryState == InstaChatDeliveryState.FAILED }
      .forEach { message ->
        val payload = when {
          message.attachment?.localUri != null -> PendingPayload.Media(
            message.attachment.localUri,
            message.attachment.contentType,
            message.attachment.takeIf { !it.id.startsWith("local-") },
          )
          message.location != null -> PendingPayload.Location(message.location)
          else -> PendingPayload.Text(message.content)
        }
        pending[message.id] = payload
      }
  }
}

internal fun matchesLocalEcho(local: InstaChatMessage, incoming: InstaChatMessage, currentUserId: String): Boolean {
  if (!local.id.startsWith("local-") || incoming.senderId != currentUserId || local.senderId != currentUserId) return false
  if (Duration.between(local.createdAt, incoming.createdAt).abs() > Duration.ofMinutes(5)) return false
  return when {
    local.attachment != null && incoming.attachment != null -> local.attachment.type == incoming.attachment.type
    local.type == InstaChatMessageType.LOCATION -> incoming.type == InstaChatMessageType.LOCATION
    else -> local.type == incoming.type && local.content == incoming.content
  }
}

private sealed interface PendingPayload {
  data class Text(val text: String) : PendingPayload
  data class Location(val location: InstaChatLocation) : PendingPayload
  data class Media(val uri: Uri, val contentType: String, val uploaded: InstaChatAttachment?) : PendingPayload
}
