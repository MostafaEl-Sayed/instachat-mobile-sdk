package pro.instakit.instachat.android

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant

class MessagePreviewTest {
  @Test fun attachmentPreviewsNeverExposeFileNames() {
    fun message(type: InstaChatAttachmentType, name: String) = InstaChatMessage(
      id = type.name,
      roomId = "room",
      senderId = "user",
      content = name,
      type = if (type == InstaChatAttachmentType.IMAGE) InstaChatMessageType.IMAGE else InstaChatMessageType.FILE,
      createdAt = Instant.EPOCH,
      attachment = InstaChatAttachment("a", name, "application/octet-stream", type, url = "https://cdn.test/$name"),
    )
    assertEquals("Photo", message(InstaChatAttachmentType.IMAGE, "private-photo.jpg").roomPreview)
    assertEquals("Video", message(InstaChatAttachmentType.VIDEO, "local-123.mov").roomPreview)
    assertEquals("Voice note", message(InstaChatAttachmentType.AUDIO, "recording.m4a").roomPreview)
    assertEquals("File", message(InstaChatAttachmentType.FILE, "contract.pdf").roomPreview)
  }
}
