import Foundation

/// Typed errors thrown by the media processors
enum MediaToolkitError: Error, LocalizedError {
  case invalidInput(String)
  case processingFailed(String)
  case unsupported(String)

  var errorDescription: String? {
    switch self {
    case .invalidInput(let m):      return "MediaToolkit invalid input: \(m)"
    case .processingFailed(let m):  return "MediaToolkit processing failed: \(m)"
    case .unsupported(let m):       return "MediaToolkit unsupported: \(m)"
    }
  }
}

/// Utility helpers for safely resolving URIs, Foundation URLs, and filesystem paths.
enum MediaUtils {
  /// Resolves any input URI (file:// with fragments/query, plain paths, or custom schemes)
  /// into a proper Foundation URL.
  static func resolveURL(from uri: String) -> URL {
    if uri.hasPrefix("file://") {
      if let parsed = URL(string: uri) {
        return parsed
      }
      let stripped = String(uri.dropFirst(7))
      return URL(fileURLWithPath: stripped)
    }
    if uri.hasPrefix("/") {
      return URL(fileURLWithPath: uri)
    }
    if let parsed = URL(string: uri) {
      return parsed
    }
    return URL(fileURLWithPath: uri)
  }

  /// Extracts the clean filesystem path from a URI or URL, stripping fragments/query and decoding percent escapes.
  static func resolveFilePath(from uri: String) -> String {
    let url = resolveURL(from: uri)
    if url.isFileURL {
      return url.path
    }
    if uri.hasPrefix("file://") {
      let stripped = String(uri.dropFirst(7))
      if let hashIdx = stripped.firstIndex(of: "#") {
        let base = String(stripped[..<hashIdx])
        return base.removingPercentEncoding ?? base
      }
      return stripped.removingPercentEncoding ?? stripped
    }
    return uri
  }
}

