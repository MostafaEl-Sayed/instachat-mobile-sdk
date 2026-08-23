package pro.instakit.instachat.android

import org.junit.Assert.assertEquals
import org.junit.Test

class LocationSelectionTest {
  @Test
  fun mapSelectionKeepsTheConfirmedCoordinate() {
    val location = selectedMapLocation(30.0444, 31.2357)

    assertEquals(30.0444, location.latitude, 0.0)
    assertEquals(31.2357, location.longitude, 0.0)
    assertEquals("Selected location", location.name)
  }

  @Test
  fun mapSelectionClampsCoordinatesToBackendSafeRanges() {
    val location = selectedMapLocation(100.0, -200.0)

    assertEquals(90.0, location.latitude, 0.0)
    assertEquals(-180.0, location.longitude, 0.0)
  }
}
