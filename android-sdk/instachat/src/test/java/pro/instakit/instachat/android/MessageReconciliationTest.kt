package pro.instakit.instachat.android

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class MessageReconciliationTest {
  @Test fun matchingBackendEchoReplacesOptimisticMessage() {
    val now = Instant.parse("2026-08-15T10:00:00Z")
    val local = InstaChatMessage("local-1", "room", "user-1", content = "Hello", type = InstaChatMessageType.TEXT, createdAt = now)
    val echo = InstaChatMessage("server-1", "room", "user-1", content = "Hello", type = InstaChatMessageType.TEXT, createdAt = now.plusSeconds(1))
    assertTrue(matchesLocalEcho(local, echo, "user-1"))
  }

  @Test fun receivedProviderMessageNeverConsumesLocalEcho() {
    val now = Instant.parse("2026-08-15T10:00:00Z")
    val local = InstaChatMessage("local-1", "room", "user-1", content = "Hello", type = InstaChatMessageType.TEXT, createdAt = now)
    val incoming = InstaChatMessage("server-2", "room", "provider", content = "Hello", type = InstaChatMessageType.TEXT, createdAt = now)
    assertFalse(matchesLocalEcho(local, incoming, "user-1"))
  }
}
