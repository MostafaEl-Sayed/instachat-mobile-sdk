package pro.instakit.instachat.android

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class MediaRetryPolicyTest {
  @Test fun transientCdnStatusesAreRetried() {
    listOf(400, 404, 408, 425, 429, 500, 502, 503).forEach { status ->
      assertTrue("Expected $status to be retryable", MediaRetryDelays.isTransientStatus(status))
    }
  }

  @Test fun permanentClientErrorsAreNotRetried() {
    listOf(401, 403, 405, 410, 422).forEach { status ->
      assertFalse("Expected $status to be permanent", MediaRetryDelays.isTransientStatus(status))
    }
  }

  @Test fun connectionFailuresAreRetried() {
    assertTrue(MediaRetryDelays.isTransient(IOException("connection reset")))
  }
}
