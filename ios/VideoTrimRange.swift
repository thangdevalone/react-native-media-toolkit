import Foundation

struct VideoTrimRange {
  let startMs: Double
  let endMs: Double

  struct ValidationError: LocalizedError {
    let errorDescription: String?
  }

  static func resolve(startMs: Double?, endMs: Double?, durationMs: Double) throws -> VideoTrimRange? {
    guard startMs != nil || endMs != nil else { return nil }
    guard durationMs.isFinite, durationMs > 0 else {
      throw ValidationError(errorDescription: "Cannot determine video duration for trimming.")
    }
    let start = startMs ?? 0
    let end = endMs ?? durationMs
    guard start.isFinite, end.isFinite, start >= 0, end > start, end <= durationMs else {
      throw ValidationError(errorDescription: "Trim range [\(start), \(end)]ms must satisfy 0 <= startTime < endTime <= \(durationMs)ms.")
    }
    guard end - start >= 1 else {
      throw ValidationError(errorDescription: "Trim range must span at least one millisecond.")
    }
    return VideoTrimRange(startMs: start, endMs: end)
  }
}
