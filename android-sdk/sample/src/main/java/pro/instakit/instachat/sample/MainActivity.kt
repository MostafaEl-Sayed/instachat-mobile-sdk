package pro.instakit.instachat.sample

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import pro.instakit.instachat.android.InstaChat
import pro.instakit.instachat.android.InstaChatUser

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent {
      MaterialTheme {
        var token by rememberSaveable { mutableStateOf(intent.getStringExtra("token").orEmpty()) }
        var roomId by rememberSaveable { mutableStateOf("") }
        var error by rememberSaveable { mutableStateOf<String?>(null) }
        Surface(color = Color(0xFFF2F2F7)) {
          Column(
            Modifier.fillMaxSize().statusBarsPadding().padding(24.dp),
            verticalArrangement = Arrangement.Center,
          ) {
            Text("InstaChat Android", fontSize = 32.sp, fontWeight = FontWeight.Bold)
            Text("Native SDK integration sample", color = Color.Gray)
            Spacer(Modifier.height(24.dp))
            OutlinedTextField(token, { token = it }, label = { Text("InstaChat token") }, modifier = Modifier.fillMaxWidth(), minLines = 3)
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(roomId, { roomId = it }, label = { Text("Room ID (optional)") }, modifier = Modifier.fillMaxWidth())
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp)) }
            Spacer(Modifier.height(18.dp))
            Button(
              onClick = {
                runCatching {
                  val sdk = InstaChat.initialize(
                    context = this@MainActivity,
                    baseUrl = "https://instachat.instakit.pro",
                    token = token,
                    user = InstaChatUser("user-1", "Mostafa"),
                  )
                  if (roomId.isBlank()) sdk.openChatList(this@MainActivity) else sdk.openChat(this@MainActivity, roomId.trim())
                }.onFailure { error = it.message }
              },
              modifier = Modifier.fillMaxWidth().height(52.dp),
              shape = RoundedCornerShape(8.dp),
            ) { Text(if (roomId.isBlank()) "Open chat list" else "Open room") }
          }
        }
      }
    }
  }
}
