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
