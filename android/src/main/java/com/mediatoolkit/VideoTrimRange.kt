package com.margelo.nitro.com.mediatoolkit

/** A validated range in Media3's millisecond timebase. */
internal data class VideoTrimRange(val startMs: Long, val endMs: Long) {
  companion object {
    fun resolve(startMs: Double?, endMs: Double?, durationMs: Long): VideoTrimRange? {
      if (startMs == null && endMs == null) return null

      require(durationMs > 0) { "Cannot determine video duration for trimming." }
      val start = startMs ?: 0.0
      val end = endMs ?: durationMs.toDouble()
      require(start.isFinite() && end.isFinite() && start >= 0 && end > start && end <= durationMs.toDouble()) {
        "Trim range [$start, $end]ms must satisfy 0 <= startTime < endTime <= ${durationMs}ms."
      }
      require(end - start >= 1) { "Trim range must span at least one millisecond." }

      val range = VideoTrimRange(start.toLong(), end.toLong())
      require(range.endMs > range.startMs) { "Trim range must span at least one millisecond." }
      return range
    }
  }
}
