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

  @Test fun mediaEchoMatchesTheOriginalFileOnly() {
    val now = Instant.parse("2026-08-15T10:00:00Z")
    val local = mediaMessage("local-1", "local-attachment-1", "first-video.mov", now)
    val matching = mediaMessage("server-1", "attachment-1", "first-video.mov", now.plusSeconds(2))
    val different = mediaMessage("server-2", "attachment-2", "second-video.mov", now.plusSeconds(2))

    assertTrue(matchesLocalEcho(local, matching, "user-1"))
    assertFalse(matchesLocalEcho(local, different, "user-1"))
  }

  private fun mediaMessage(id: String, attachmentId: String, fileName: String, createdAt: Instant) =
    InstaChatMessage(
      id = id,
      roomId = "room",
      senderId = "user-1",
      content = fileName,
      type = InstaChatMessageType.FILE,
      createdAt = createdAt,
      attachment = InstaChatAttachment(
        id = attachmentId,
        fileName = fileName,
        contentType = "video/quicktime",
        type = InstaChatAttachmentType.VIDEO,
        url = "https://cdn.example.com/$fileName",
      ),
    )
}
