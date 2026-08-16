package pro.instakit.instachat.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DataLoadingTest {
  @Test
  fun emptyPaginationCursorsTerminateHistoryLoading() {
    assertNull(null.normalizedCursor())
    assertNull("".normalizedCursor())
    assertNull("   ".normalizedCursor())
  }

  @Test
  fun paginationCursorIsTrimmedAndPreserved() {
    assertEquals("next-page", "  next-page  ".normalizedCursor())
  }

  @Test
  fun transparentPlaceholderDimensionsAreNotPresentedAsLoadedMedia() {
    assertTrue(isUnusableImagePayload(fileSize = 68))
    assertTrue(isUnusableImagePayload(fileSize = null, width = 1, height = 1))
    assertFalse(isUnusableImagePayload(fileSize = 4_096, width = 2, height = 1))
    assertFalse(isUnusableImagePayload(fileSize = 4_096, width = 1, height = 2))
    assertFalse(isUnusableImagePayload(fileSize = 2_000_000, width = 1080, height = 1920))
  }
}
