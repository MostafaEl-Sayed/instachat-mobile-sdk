package pro.instakit.instachat.android

import org.junit.Assert.assertEquals
import org.junit.Test

class SenderIdentityTest {
  @Test
  fun `user token maps only the authenticated user sender to the outgoing side`() {
    val identity = TokenIdentity(subject = "user-uuid", externalUserId = "user_291")

    assertEquals("291", resolveSenderId("user-uuid", "291", identity))
    assertEquals("provider-uuid", resolveSenderId("provider-uuid", "291", identity))
  }

  @Test
  fun `provider token maps only the authenticated provider sender to the outgoing side`() {
    val identity = TokenIdentity(subject = "provider-uuid", externalUserId = "provider_345")

    assertEquals("345", resolveSenderId("provider-uuid", "345", identity))
    assertEquals("user-uuid", resolveSenderId("user-uuid", "345", identity))
  }
}
