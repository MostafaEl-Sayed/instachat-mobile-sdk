package pro.instakit.instachat.android

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.BrokenImage
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.os.CancellationSignal
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import coil.request.CachePolicy
import coil.request.ImageRequest
import kotlinx.coroutines.delay
import okhttp3.Headers
import java.io.File
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.max

@Composable
internal fun InstaChatTheme(content: @Composable () -> Unit) {
  MaterialTheme(
    colorScheme = androidx.compose.material3.lightColorScheme(
      primary = Color(0xFF0A84FF),
      background = Color(0xFFF2F2F7),
      surface = Color.White,
      onPrimary = Color.White,
      onBackground = Color(0xFF111111),
    ),
    content = content,
  )
}

@Composable
internal fun InstaChatRoot(
  sdk: InstaChatSDK,
  initialRoomId: String?,
  initialRoomTitle: String?,
  modifier: Modifier = Modifier,
  onClose: (() -> Unit)? = null,
) {
  val state by sdk.store.state.collectAsState()
  val context = LocalContext.current
  var selectedRoom by rememberSaveable { mutableStateOf(initialRoomId) }
  var selectedTitle by rememberSaveable { mutableStateOf(initialRoomTitle) }
  val playback = remember(sdk) { MediaPlaybackController(context, sdk.configuration) }

  DisposableEffect(Unit) { onDispose { playback.release(); sdk.store.closeRoom() } }

  Surface(modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
    if (selectedRoom == null) {
      ChatRoomList(
        state = state,
        title = sdk.configuration.title,
        onRefresh = sdk.store::loadRooms,
        onRoom = { room -> selectedRoom = room.id; selectedTitle = room.title },
        onClose = onClose,
      )
    } else {
      val room = state.rooms.firstOrNull { it.id == selectedRoom }
        ?: InstaChatRoom(selectedRoom!!, selectedTitle ?: "Chat")
      ChatDetail(
        state = state,
        room = room,
        currentUserId = sdk.configuration.user.id,
        configuration = sdk.configuration,
        store = sdk.store,
        playback = playback,
        onBack = if (initialRoomId == null) ({ sdk.store.closeRoom(); selectedRoom = null; sdk.store.loadRooms() }) else null,
        onClose = onClose,
      )
    }
  }
}

@Composable
private fun ChatRoomList(
  state: InstaChatState,
  title: String,
  onRefresh: () -> Unit,
  onRoom: (InstaChatRoom) -> Unit,
  onClose: (() -> Unit)?,
) {
  val lifecycleOwner = LocalLifecycleOwner.current
  LaunchedEffect(Unit) { onRefresh() }
  DisposableEffect(lifecycleOwner) {
    val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) onRefresh() }
    lifecycleOwner.lifecycle.addObserver(observer)
    onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
  }

  Column(Modifier.fillMaxSize().statusBarsPadding()) {
    Header(title = title, onClose = onClose)
    if (state.loadingRooms && state.rooms.isEmpty()) {
      Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
    } else if (state.rooms.isEmpty()) {
      EmptyState("No conversations yet", "Your conversations will appear here.", onRefresh)
    } else {
      LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
      ) {
        items(state.rooms, key = { it.id }) { room ->
          RoomRow(room, onClick = { onRoom(room) })
          HorizontalDivider(color = Color(0xFFE5E5EA))
        }
      }
    }
  }
}

@Composable
private fun Header(title: String, onBack: (() -> Unit)? = null, onClose: (() -> Unit)?) {
  Box(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 8.dp)) {
    if (onBack != null) {
      IconButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart).size(48.dp)) {
        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
      }
    }
    Text(
      text = title,
      fontWeight = FontWeight.SemiBold,
      fontSize = 18.sp,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier.align(Alignment.Center).padding(horizontal = 56.dp),
    )
    if (onClose != null) {
      IconButton(onClick = onClose, modifier = Modifier.align(Alignment.CenterEnd).size(44.dp)) {
        Icon(Icons.Default.Close, "Close chat", modifier = Modifier.size(20.dp))
      }
    }
  }
}

@Composable
private fun RoomRow(room: InstaChatRoom, onClick: () -> Unit) {
  Row(
    Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 14.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    AsyncImage(
      model = room.avatarUrl,
      contentDescription = null,
      modifier = Modifier.size(52.dp).clip(CircleShape).background(Color(0xFFE9E9EE)),
    )
    Spacer(Modifier.width(12.dp))
    Column(Modifier.weight(1f)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Text(room.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, maxLines = 1, modifier = Modifier.weight(1f))
        room.updatedAt?.let { Text(formatRoomTime(it), color = Color.Gray, fontSize = 13.sp) }
      }
      Spacer(Modifier.height(4.dp))
      Row(verticalAlignment = Alignment.CenterVertically) {
        Text(room.subtitle ?: "", color = Color(0xFF6E6E73), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        if (room.unreadCount > 0) {
          Box(Modifier.size(22.dp).background(Color(0xFFFF3B30), CircleShape), contentAlignment = Alignment.Center) {
            Text(room.unreadCount.coerceAtMost(99).toString(), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
          }
        }
      }
    }
  }
}

@Composable
private fun ChatDetail(
  state: InstaChatState,
  room: InstaChatRoom,
  currentUserId: String,
  configuration: InstaChatConfiguration,
  store: InstaChatStore,
  playback: MediaPlaybackController,
  onBack: (() -> Unit)?,
  onClose: (() -> Unit)?,
) {
  val messages = state.messagesByRoom[room.id].orEmpty()
  val listState = remember(room.id) { androidx.compose.foundation.lazy.LazyListState() }
  var positionedAtLatest by remember(room.id) { mutableStateOf(false) }
  LaunchedEffect(room.id) { store.openRoom(room) }
  LaunchedEffect(messages.lastOrNull()?.id, room.id) {
    val newest = messages.lastOrNull() ?: return@LaunchedEffect
    if (!positionedAtLatest) {
      listState.scrollToItem(0)
      positionedAtLatest = true
    } else if (newest.senderId == currentUserId || listState.firstVisibleItemIndex <= 1) {
      listState.animateScrollToItem(0)
    }
  }
  DisposableEffect(room.id) { onDispose { store.closeRoom() } }

  Scaffold(
    modifier = Modifier.fillMaxSize().statusBarsPadding(),
    topBar = { Header(room.title, onBack, onClose) },
    bottomBar = {
      ChatComposer(
        roomId = room.id,
        store = store,
        modifier = Modifier.navigationBarsPadding().imePadding(),
      )
    },
    containerColor = Color(0xFFF2F2F7),
    contentWindowInsets = WindowInsets(0),
  ) { padding ->
    if (room.id in state.loadingRoomIds && messages.isEmpty()) {
      Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
    } else {
      LazyColumn(
        state = listState,
        reverseLayout = true,
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
      ) {
        if (room.id in state.typingRoomIds) item(key = "typing") { TypingBubble() }
        items(messages.asReversed(), key = { it.id }) { message ->
          MessageBubble(message, message.senderId == currentUserId, configuration, playback, onRetry = { store.retry(message.id) })
        }
        item(key = "older") {
          when {
            room.id in state.loadingOlderRoomIds -> Box(
              Modifier.fillMaxWidth().padding(12.dp),
              contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp) }
            room.id in state.historyErrorRoomIds -> Box(
              Modifier.fillMaxWidth().padding(8.dp),
              contentAlignment = Alignment.Center,
            ) {
              TextButton(onClick = { store.loadOlder(room.id) }) {
                Icon(Icons.Default.Refresh, null)
                Spacer(Modifier.width(4.dp))
                Text("Retry older messages")
              }
            }
            else -> LaunchedEffect(messages.firstOrNull()?.id) {
              if (messages.isNotEmpty()) store.loadOlder(room.id)
            }
          }
        }
      }
    }
  }
}

@Composable
private fun MessageBubble(
  message: InstaChatMessage,
  outgoing: Boolean,
  configuration: InstaChatConfiguration,
  playback: MediaPlaybackController,
  onRetry: () -> Unit,
) {
  var showImage by remember(message.id) { mutableStateOf(false) }
  var showVideo by remember(message.id) { mutableStateOf(false) }
  var showLocation by remember(message.id) { mutableStateOf(false) }
  val bubble = if (outgoing) MaterialTheme.colorScheme.primary else Color.White
  val foreground = if (outgoing) Color.White else Color(0xFF111111)
  Column(Modifier.fillMaxWidth(), horizontalAlignment = if (outgoing) Alignment.End else Alignment.Start) {
    Surface(color = bubble, shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth(0.82f)) {
      Column(Modifier.padding(10.dp)) {
        when {
          message.type == InstaChatMessageType.TEXT -> LinkedMessageText(message.content, foreground)
          message.type == InstaChatMessageType.LOCATION -> LocationBubble(message, foreground) { showLocation = true }
          message.attachment?.type == InstaChatAttachmentType.IMAGE -> ImageBubble(message, configuration) { showImage = true }
          message.attachment?.type == InstaChatAttachmentType.VIDEO -> VideoBubble(message, foreground) { showVideo = true }
          message.attachment?.type == InstaChatAttachmentType.AUDIO -> AudioBubble(message, foreground, playback)
          else -> FileBubble(message, foreground)
        }
        Spacer(Modifier.height(4.dp))
        Text(formatMessageTime(message.createdAt), color = foreground.copy(alpha = 0.68f), fontSize = 11.sp, modifier = Modifier.align(Alignment.End))
      }
    }
    if (message.deliveryState == InstaChatDeliveryState.FAILED) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Text(message.failureMessage ?: "Could not send.", color = Color(0xFFB42318), fontSize = 12.sp)
        TextButton(onClick = onRetry, contentPadding = PaddingValues(horizontal = 8.dp)) {
          Icon(Icons.Default.Refresh, null, Modifier.size(15.dp)); Spacer(Modifier.width(3.dp)); Text("Retry")
        }
      }
    } else if (message.deliveryState == InstaChatDeliveryState.SENDING) {
      Text("Sending...", color = Color.Gray, fontSize = 11.sp)
    }
  }
  if (showImage) FullImageDialog(message, configuration) { showImage = false }
  if (showVideo) VideoDialog(message, playback) { showVideo = false }
  if (showLocation) LocationDialog(message.location, onDismiss = { showLocation = false })
}

@Composable
private fun LinkedMessageText(text: String, color: Color) {
  val regex = remember { Regex("https?://[^\\s]+", RegexOption.IGNORE_CASE) }
  val annotated = buildAnnotatedString {
    var cursor = 0
    regex.findAll(text).forEach { match ->
      append(text.substring(cursor, match.range.first))
      withLink(LinkAnnotation.Url(match.value, TextLinkStyles(SpanStyle(color = if (color == Color.White) Color(0xFFB9DCFF) else Color(0xFF0066CC), textDecoration = TextDecoration.Underline)))) {
        append(match.value)
      }
      cursor = match.range.last + 1
    }
    append(text.substring(cursor))
  }
  Text(annotated, color = color, fontSize = 16.sp)
}

@Composable
private fun ImageBubble(message: InstaChatMessage, configuration: InstaChatConfiguration, onOpen: () -> Unit) {
  val attachment = message.attachment ?: return
  var attempt by remember(message.id) { mutableIntStateOf(0) }
  var failed by remember(message.id) { mutableStateOf(false) }
  var loading by remember(message.id) { mutableStateOf(true) }
  var unusable by remember(message.id) { mutableStateOf(isUnusableImagePayload(attachment.fileSize)) }
  var preferRemote by remember(message.id) { mutableStateOf(false) }
  LaunchedEffect(failed, attempt, preferRemote) {
    if (!failed) return@LaunchedEffect
    if (!preferRemote && attachment.hasUsableLocalFile()) {
      preferRemote = true
      failed = false
      return@LaunchedEffect
    }
    val delayMs = MediaRetryDelays.milliseconds.getOrNull(attempt) ?: return@LaunchedEffect
    delay(delayMs)
    attempt++
    failed = false
  }
  Box(Modifier.fillMaxWidth().height(210.dp).clip(RoundedCornerShape(12.dp)).background(Color(0xFFE5E5EA))) {
    AsyncImage(
      model = imageRequest(attachment, configuration, attempt, preferRemote),
      contentDescription = "Open photo",
      onLoading = { loading = true },
      onError = { loading = false; failed = true },
      onSuccess = { result ->
        loading = false
        failed = false
        unusable = isUnusableImagePayload(
          attachment.fileSize,
          result.result.drawable.intrinsicWidth,
          result.result.drawable.intrinsicHeight,
        )
      },
      modifier = Modifier.fillMaxSize().clickable(enabled = !failed && !unusable, onClick = onOpen),
    )
    if (loading && !failed && !unusable) CircularProgressIndicator(Modifier.align(Alignment.Center).size(28.dp), strokeWidth = 2.dp)
    if (unusable) MediaUnavailable(
      label = "Photo data is unavailable",
      onRetry = { attempt++; unusable = false; loading = true },
      modifier = Modifier.align(Alignment.Center),
    )
    if (failed && attempt >= MediaRetryDelays.milliseconds.size) MediaUnavailable(
      label = "Photo could not be loaded",
      onRetry = { attempt++; failed = false; loading = true },
      modifier = Modifier.align(Alignment.Center),
    )
  }
}

@Composable
private fun MediaUnavailable(label: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
  Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
    Icon(Icons.Default.BrokenImage, null, tint = Color(0xFF6E6E73))
    Spacer(Modifier.height(4.dp))
    Text(label, color = Color(0xFF6E6E73), fontSize = 13.sp)
    TextButton(onClick = onRetry) {
      Icon(Icons.Default.Refresh, null, Modifier.size(16.dp))
      Spacer(Modifier.width(4.dp))
      Text("Retry")
    }
  }
}

@Composable
private fun VideoBubble(message: InstaChatMessage, color: Color, onOpen: () -> Unit) {
  Row(Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(Icons.Default.PlayArrow, "Play video", tint = color, modifier = Modifier.size(38.dp))
    Spacer(Modifier.width(8.dp))
    Column { Text("Video", color = color, fontWeight = FontWeight.Medium); Text("Tap to preview", color = color.copy(alpha = .7f), fontSize = 12.sp) }
  }
}

@Composable
private fun AudioBubble(message: InstaChatMessage, color: Color, playback: MediaPlaybackController) {
  val playbackState by playback.state.collectAsState()
  val active = playbackState.messageId == message.id
  Row(Modifier.fillMaxWidth().clickable { playback.toggle(message) }.padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
    if (active && playbackState.isLoading) CircularProgressIndicator(Modifier.size(34.dp), strokeWidth = 3.dp, color = color)
    else Icon(if (active && playbackState.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, "Play voice note", tint = color, modifier = Modifier.size(36.dp))
    Spacer(Modifier.width(8.dp))
    Waveform(List(24) { ((it * 17 + message.id.hashCode()).mod(9) + 2) / 10f }, color, Modifier.weight(1f).height(34.dp))
    if (active && playbackState.error != null) IconButton(onClick = { playback.play(message) }) { Icon(Icons.Default.Download, "Retry voice note", tint = color) }
  }
}

@Composable
private fun FileBubble(message: InstaChatMessage, color: Color) {
  val context = LocalContext.current
  Row(Modifier.fillMaxWidth().clickable {
    message.attachment?.let { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it.url))) } }
  }.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(Icons.Default.Download, "Open file", tint = color)
    Spacer(Modifier.width(8.dp)); Text("File", color = color)
  }
}

@Composable
private fun LocationBubble(message: InstaChatMessage, color: Color, onOpen: () -> Unit) {
  val location = message.location
  Column(Modifier.fillMaxWidth().clickable(enabled = location != null, onClick = onOpen).padding(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    Icon(Icons.Default.LocationOn, "Open location", tint = color, modifier = Modifier.size(42.dp))
    Text(location?.name ?: "Shared location", color = color, fontWeight = FontWeight.SemiBold)
    location?.let { Text("%.5f, %.5f".format(it.latitude, it.longitude), color = color.copy(alpha = .72f), fontSize = 12.sp) }
  }
}

@Composable
private fun ChatComposer(roomId: String, store: InstaChatStore, modifier: Modifier = Modifier) {
  val context = LocalContext.current
  var text by rememberSaveable(roomId) { mutableStateOf("") }
  var menu by remember { mutableStateOf(false) }
  val recorder = remember { VoiceNoteRecorder(context) }
  val recording by recorder.state.collectAsState()
  val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris -> store.sendMedia(roomId, uris.take(5)) }
  val videoPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> uri?.let { store.sendMedia(roomId, listOf(it)) } }
  val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { if (it) recorder.start() }
  val locationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
    if (granted.values.any { it }) currentLocation(context) { location ->
      if (location != null) store.sendLocation(roomId, location) else store.dismissError()
    }
  }

  DisposableEffect(Unit) { onDispose { recorder.cancel() } }
  Surface(modifier.fillMaxWidth(), color = Color.White, shadowElevation = 1.dp) {
    if (recording.isRecording) {
      Row(Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = recorder::cancel) { Icon(Icons.Default.Delete, "Cancel recording", tint = Color(0xFFFF3B30)) }
        Text(formatDuration(recording.elapsedMillis), fontSize = 15.sp, modifier = Modifier.width(48.dp))
        Waveform(recording.amplitudes, MaterialTheme.colorScheme.primary, Modifier.weight(1f).height(38.dp))
        IconButton(onClick = { recorder.finish()?.let { store.sendMedia(roomId, listOf(it), "audio/mp4") } }) {
          Icon(Icons.AutoMirrored.Filled.Send, "Send voice note", tint = MaterialTheme.colorScheme.primary)
        }
      }
    } else {
      Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom) {
        Box {
          IconButton(onClick = { menu = true }) { Icon(Icons.Default.Add, "Attachments", tint = MaterialTheme.colorScheme.primary) }
          DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text("Share location") }, leadingIcon = { Icon(Icons.Default.LocationOn, null) }, onClick = {
              menu = false
              locationPermission.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
            })
            DropdownMenuItem(text = { Text("Send photos") }, leadingIcon = { Icon(Icons.Default.Image, null) }, onClick = { menu = false; imagePicker.launch("image/*") })
            DropdownMenuItem(text = { Text("Send video") }, leadingIcon = { Icon(Icons.Default.Videocam, null) }, onClick = { menu = false; videoPicker.launch("video/*") })
          }
        }
        IconButton(onClick = {
          if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) recorder.start()
          else micPermission.launch(Manifest.permission.RECORD_AUDIO)
        }) { Icon(Icons.Default.Mic, "Record voice note", tint = MaterialTheme.colorScheme.primary) }
        BasicTextField(
          value = text,
          onValueChange = { text = it; store.sendTyping(roomId) },
          modifier = Modifier.weight(1f).heightIn(min = 44.dp, max = 120.dp).clip(RoundedCornerShape(22.dp)).background(Color(0xFFF2F2F7)).padding(horizontal = 14.dp, vertical = 11.dp),
          maxLines = 5,
          textStyle = MaterialTheme.typography.bodyLarge.copy(color = Color(0xFF111111)),
          decorationBox = { inner -> Box { if (text.isEmpty()) Text("Message", color = Color(0xFF8E8E93)); inner() } },
        )
        IconButton(onClick = { val value = text; text = ""; store.sendText(roomId, value) }, enabled = text.isNotBlank()) {
          Icon(Icons.AutoMirrored.Filled.Send, "Send message", tint = if (text.isNotBlank()) MaterialTheme.colorScheme.primary else Color(0xFFC7C7CC))
        }
      }
    }
  }
}

@Composable
private fun Waveform(amplitudes: List<Float>, color: Color, modifier: Modifier = Modifier) {
  androidx.compose.foundation.Canvas(modifier) {
    if (amplitudes.isEmpty()) return@Canvas
    val spacing = size.width / amplitudes.size
    amplitudes.forEachIndexed { index, amplitude ->
      val lineHeight = size.height * amplitude.coerceIn(.08f, 1f)
      drawLine(color, androidx.compose.ui.geometry.Offset(index * spacing + spacing / 2, (size.height - lineHeight) / 2), androidx.compose.ui.geometry.Offset(index * spacing + spacing / 2, (size.height + lineHeight) / 2), strokeWidth = 3.dp.toPx(), cap = StrokeCap.Round)
    }
  }
}

@Composable
private fun FullImageDialog(message: InstaChatMessage, configuration: InstaChatConfiguration, onDismiss: () -> Unit) {
  val attachment = message.attachment ?: return
  var attempt by remember(message.id) { mutableIntStateOf(0) }
  var failed by remember(message.id) { mutableStateOf(false) }
  var loading by remember(message.id) { mutableStateOf(true) }
  var unusable by remember(message.id) { mutableStateOf(isUnusableImagePayload(attachment.fileSize)) }
  var preferRemote by remember(message.id) { mutableStateOf(false) }
  LaunchedEffect(failed, attempt, preferRemote) {
    if (!failed) return@LaunchedEffect
    if (!preferRemote && attachment.hasUsableLocalFile()) {
      preferRemote = true
      failed = false
      return@LaunchedEffect
    }
    val delayMs = MediaRetryDelays.milliseconds.getOrNull(attempt) ?: return@LaunchedEffect
    delay(delayMs)
    attempt++
    failed = false
  }
  androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
    Box(Modifier.fillMaxSize().background(Color.Black)) {
      AsyncImage(
        model = imageRequest(attachment, configuration, attempt, preferRemote),
        contentDescription = "Full-screen photo",
        onLoading = { loading = true },
        onError = { loading = false; failed = true },
        onSuccess = { result ->
          loading = false
          failed = false
          unusable = isUnusableImagePayload(
            attachment.fileSize,
            result.result.drawable.intrinsicWidth,
            result.result.drawable.intrinsicHeight,
          )
        },
        modifier = Modifier.fillMaxSize(),
      )
      if (loading && !failed && !unusable) CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White)
      if (unusable) MediaUnavailable(
        label = "Photo data is unavailable",
        onRetry = { attempt++; unusable = false; loading = true },
        modifier = Modifier.align(Alignment.Center),
      )
      if (failed && attempt >= MediaRetryDelays.milliseconds.size) {
        Button(onClick = { attempt++; failed = false; loading = true }, Modifier.align(Alignment.Center)) {
          Icon(Icons.Default.Refresh, null); Text(" Retry photo")
        }
      }
      IconButton(onClick = onDismiss, Modifier.align(Alignment.TopEnd).padding(12.dp).background(Color.Black.copy(alpha = .5f), CircleShape)) { Icon(Icons.Default.Close, "Close photo", tint = Color.White) }
    }
  }
}

@Composable
private fun VideoDialog(message: InstaChatMessage, playback: MediaPlaybackController, onDismiss: () -> Unit) {
  val state by playback.state.collectAsState()
  LaunchedEffect(message.id) { playback.play(message) }
  DisposableEffect(message.id) { onDispose { playback.stop(message.id) } }
  androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
    Surface(color = Color.Black, shape = RoundedCornerShape(8.dp), modifier = Modifier.fillMaxWidth().fillMaxHeight(.72f)) {
      Box {
        playback.playerFor(message.id)?.let { player -> AndroidView(factory = { PlayerView(it).apply { this.player = player; useController = true } }, modifier = Modifier.fillMaxSize()) }
        if (state.messageId == message.id && state.isLoading) CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White)
        if (state.messageId == message.id && state.error != null) Button(onClick = { playback.play(message) }, Modifier.align(Alignment.Center)) { Icon(Icons.Default.Refresh, null); Text(" Retry video") }
        IconButton(onClick = onDismiss, Modifier.align(Alignment.TopEnd).padding(8.dp).background(Color.Black.copy(alpha = .5f), CircleShape)) { Icon(Icons.Default.Close, "Close video", tint = Color.White) }
      }
    }
  }
}

@Composable
private fun LocationDialog(location: InstaChatLocation?, onDismiss: () -> Unit) {
  val context = LocalContext.current
  if (location == null) return
  AlertDialog(
    onDismissRequest = onDismiss,
    title = { Text(location.name ?: "Shared location") },
    text = { Text("%.6f, %.6f".format(location.latitude, location.longitude)) },
    confirmButton = { TextButton(onClick = {
      val uri = Uri.parse("geo:${location.latitude},${location.longitude}?q=${location.latitude},${location.longitude}")
      runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
      onDismiss()
    }) { Text("Open maps") } },
    dismissButton = { TextButton(onClick = {
      (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Location", "${location.latitude},${location.longitude}")); onDismiss()
    }) { Text("Copy") } },
  )
}

@Composable
private fun TypingBubble() {
  Surface(color = Color.White, shape = RoundedCornerShape(16.dp)) { Text("Typing...", Modifier.padding(horizontal = 14.dp, vertical = 8.dp), color = Color.Gray) }
}

@Composable
private fun EmptyState(title: String, subtitle: String, onRetry: () -> Unit) {
  Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
    Text(title, fontSize = 20.sp, fontWeight = FontWeight.SemiBold); Spacer(Modifier.height(8.dp)); Text(subtitle, color = Color.Gray); Spacer(Modifier.height(16.dp)); TextButton(onClick = onRetry) { Text("Refresh") }
  }
}

private fun imageRequest(
  attachment: InstaChatAttachment,
  configuration: InstaChatConfiguration,
  attempt: Int,
  preferRemote: Boolean,
): ImageRequest {
  val local = attachment.localUri?.takeIf { it.scheme != "file" || it.path?.let(::File)?.isFile == true }
  val source = if (preferRemote) Uri.parse(attachment.url) else local ?: Uri.parse(attachment.url)
  return ImageRequest.Builder(InstaChatApplicationContext.context)
    .data(source)
    .memoryCacheKey("${attachment.url}#$attempt")
    .diskCacheKey("${attachment.url}#$attempt")
    .memoryCachePolicy(CachePolicy.ENABLED)
    .diskCachePolicy(CachePolicy.ENABLED)
    .apply {
      if (source.scheme?.startsWith("http") == true && shouldAuthorizeMedia(source.toString(), configuration.baseUrl)) {
        headers(Headers.Builder().add("Authorization", "Bearer ${configuration.token}").build())
      }
    }
    .build()
}

internal fun isUnusableImagePayload(fileSize: Long?, width: Int? = null, height: Int? = null): Boolean {
  if (fileSize != null && fileSize in 1..128) return true
  return width != null && height != null && width <= 1 && height <= 1
}

private fun InstaChatAttachment.hasUsableLocalFile(): Boolean = localUri?.let { uri ->
  uri.scheme != "file" || uri.path?.let(::File)?.isFile == true
} == true

private fun currentLocation(context: Context, callback: (InstaChatLocation?) -> Unit) {
  val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
    ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
  if (!granted) { callback(null); return }
  val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
  val provider = when {
    manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
    manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
    else -> { callback(null); return }
  }
  LocationManagerCompat.getCurrentLocation(manager, provider, CancellationSignal(), ContextCompat.getMainExecutor(context)) { location ->
    callback(InstaChatLocation(location.latitude, location.longitude, "Current location"))
  }
}

private fun formatRoomTime(instant: java.time.Instant): String = DateTimeFormatter.ofPattern("h:mm a").withZone(ZoneId.systemDefault()).format(instant)
private fun formatMessageTime(instant: java.time.Instant): String = formatRoomTime(instant)
private fun formatDuration(milliseconds: Long): String = "%d:%02d".format(milliseconds / 60_000, (milliseconds / 1_000) % 60)

internal object InstaChatApplicationContext {
  lateinit var context: Context
}
