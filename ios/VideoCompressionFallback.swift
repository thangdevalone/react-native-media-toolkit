import Foundation

enum VideoCompressionFallback {
  /// A trimmed export must keep the selected content, even if encoding grows it.
  static func restoreOriginalIfLarger(
    sourceURL: URL?,
    outputURL: URL,
    hasTrimRange: Bool,
    muteAudio: Bool
  ) {
    guard !hasTrimRange, !muteAudio,
          let sourceURL = sourceURL, sourceURL.isFileURL,
          let originalAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
          let originalSize = originalAttributes[.size] as? Int64, originalSize > 0,
          let outputAttributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
          let outputSize = outputAttributes[.size] as? Int64, outputSize > originalSize else {
      return
    }

    NSLog("[MediaToolkit] Encoder inflated file from %.1fMB to %.1fMB. Reverting to original.",
          Double(originalSize) / (1024 * 1024), Double(outputSize) / (1024 * 1024))
    try? FileManager.default.removeItem(at: outputURL)
    try? FileManager.default.copyItem(at: sourceURL, to: outputURL)
  }
}
