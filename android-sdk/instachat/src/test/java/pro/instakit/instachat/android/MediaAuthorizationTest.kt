package pro.instakit.instachat.android

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaAuthorizationTest {
  @Test fun externalCdnDoesNotReceiveChatAuthorization() {
    assertFalse(shouldAuthorizeMedia(
      "https://instachat.fra1.cdn.digitaloceanspaces.com/audio.m4a",
      "https://instachat.instakit.pro",
    ))
  }

  @Test fun apiHostMediaKeepsAuthorization() {
    assertTrue(shouldAuthorizeMedia(
      "https://instachat.instakit.pro/api/v1/media/1",
      "https://instachat.instakit.pro",
    ))
  }

  @Test fun differentPortDoesNotReceiveAuthorization() {
    assertFalse(shouldAuthorizeMedia("https://instachat.instakit.pro:8443/file", "https://instachat.instakit.pro"))
  }
}
