package pro.instakit.instachat.android

import android.content.Context
import android.content.Intent
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

object InstaChat {
  @Volatile private var sdk: InstaChatSDK? = null

  @JvmStatic
  fun initialize(
    context: Context,
    baseUrl: String,
    token: String,
    user: InstaChatUser,
    historyLimit: Int = 30,
    title: String = "Messages",
  ): InstaChatSDK {
    require(baseUrl.startsWith("https://") || baseUrl.startsWith("http://")) { "baseUrl must be an HTTP(S) URL." }
    require(token.isNotBlank()) { "token must not be blank." }
    InstaChatApplicationContext.context = context.applicationContext
    sdk?.close()
    return InstaChatSDK(
      context.applicationContext,
      InstaChatConfiguration(baseUrl.trimEnd('/'), token.trim(), user, historyLimit, title),
    ).also { sdk = it }
  }

  @JvmStatic
  fun openChatList(context: Context) = requireSdk().openChatList(context)

  @JvmStatic
  fun openChat(context: Context, roomId: String, title: String? = null) =
    requireSdk().openChat(context, roomId, title)

  @JvmStatic
  fun current(): InstaChatSDK? = sdk

  internal fun requireSdk(): InstaChatSDK = checkNotNull(sdk) {
    "Call InstaChat.initialize(context, baseUrl, token, user) before opening chat."
  }
}

class InstaChatSDK internal constructor(
  context: Context,
  val configuration: InstaChatConfiguration,
) {
  internal val store = InstaChatStore(configuration, context)

  fun openChatList(context: Context) {
    context.startActivity(InstaChatActivity.intent(context))
  }

  fun openChat(context: Context, roomId: String, title: String? = null) {
    context.startActivity(InstaChatActivity.intent(context, roomId, title))
  }

  @Composable
  fun ChatList(modifier: Modifier = Modifier, onClose: (() -> Unit)? = null) {
    InstaChatRoot(this, null, null, modifier, onClose)
  }

  @Composable
  fun Chat(roomId: String, title: String? = null, modifier: Modifier = Modifier, onClose: (() -> Unit)? = null) {
    InstaChatRoot(this, roomId, title, modifier, onClose)
  }

  internal fun close() = store.close()
}

@Deprecated(
  message = "Initialize once with InstaChat.initialize(), then call openChatList() or openChat().",
  replaceWith = ReplaceWith("InstaChat.initialize(context, baseUrl, token, user).openChatList(context)"),
)
fun openLegacyInstaChat(context: Context, baseUrl: String, token: String, user: InstaChatUser) {
  InstaChat.initialize(context, baseUrl, token, user).openChatList(context)
}

class InstaChatActivity : androidx.activity.ComponentActivity() {
  override fun onCreate(savedInstanceState: android.os.Bundle?) {
    super.onCreate(savedInstanceState)
    androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
    val sdk = runCatching { InstaChat.requireSdk() }.getOrElse {
      finish()
      return
    }
    val roomId = intent.getStringExtra(EXTRA_ROOM_ID)
    val roomTitle = intent.getStringExtra(EXTRA_ROOM_TITLE)
    setContent {
      InstaChatTheme {
        InstaChatRoot(sdk, roomId, roomTitle, onClose = { finish() })
      }
    }
  }

  companion object {
    private const val EXTRA_ROOM_ID = "pro.instakit.instachat.room_id"
    private const val EXTRA_ROOM_TITLE = "pro.instakit.instachat.room_title"

    internal fun intent(context: Context, roomId: String? = null, title: String? = null) =
      Intent(context, InstaChatActivity::class.java).apply {
        roomId?.let { putExtra(EXTRA_ROOM_ID, it) }
        title?.let { putExtra(EXTRA_ROOM_TITLE, it) }
        if (context !is android.app.Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
  }
}
