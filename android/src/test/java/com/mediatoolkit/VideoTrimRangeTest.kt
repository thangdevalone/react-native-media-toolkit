package com.margelo.nitro.com.mediatoolkit

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class VideoTrimRangeTest {
  @Test
  fun validatesSharedRangeContract() {
    val fixture = File(System.getProperty("mediatoolkit.testFixtures"), "video-trim-ranges.tsv")
    val cases = fixture.readLines().drop(1).filter { it.isNotBlank() }
    for (line in cases) {
      val columns = line.split('\t')
      val (name, start, end, duration, expectedStart) = columns
      val expectedEnd = columns[5]
      if (expectedStart == "error") {
        assertThrows(name, IllegalArgumentException::class.java) {
          VideoTrimRange.resolve(parse(start), parse(end), duration.toLong())
        }
      } else {
        val result = VideoTrimRange.resolve(parse(start), parse(end), duration.toLong())
        assertEquals(name, parse(expectedStart)?.toLong(), result?.startMs)
        assertEquals(name, parse(expectedEnd)?.toLong(), result?.endMs)
      }
    }
    assertEquals(25, cases.size)
  }

  private fun parse(value: String): Double? = when (value) {
    "null" -> null
    "nan" -> Double.NaN
    "inf" -> Double.POSITIVE_INFINITY
    "-inf" -> Double.NEGATIVE_INFINITY
    else -> value.toDouble()
  }
}
