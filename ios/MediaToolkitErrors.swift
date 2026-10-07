import AVFoundation
import Foundation
import Photos

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

/// Utility helpers for safely resolving URIs, Foundation URLs, PhotoKit assets, and filesystem paths.
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

  /// Fetches a PHAsset by localIdentifier if uri starts with ph://
  static func fetchPHAsset(from uri: String) -> PHAsset? {
    guard uri.hasPrefix("ph://") else { return nil }
    let raw = String(uri.dropFirst(5))
    let clean = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
    let baseId = clean.components(separatedBy: "#")[0].components(separatedBy: "?")[0]

    let candidates = [baseId, "\(baseId)/L0/001", clean, raw]
    for id in candidates {
      guard !id.isEmpty else { continue }
      let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
      if let first = result.firstObject {
        return first
      }
    }
    return nil
  }

  /// Synchronously loads an AVAsset (waiting on semaphore for ph:// if on background thread).
  static func loadAVAsset(from uri: String) -> AVAsset? {
    if uri.hasPrefix("ph://") {
      guard let phAsset = fetchPHAsset(from: uri) else { return nil }
      let options = PHVideoRequestOptions()
      options.isNetworkAccessAllowed = true
      options.deliveryMode = .highQualityFormat

      var loadedAsset: AVAsset?
      let sema = DispatchSemaphore(value: 0)
      PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, _ in
        loadedAsset = asset
        sema.signal()
      }
      _ = sema.wait(timeout: .now() + 120.0)
      return loadedAsset
    } else {
      let url = resolveURL(from: uri)
      return AVAsset(url: url)
    }
  }

  /// Asynchronously loads an AVAsset from a file URI or PhotoKit ph:// URI.
  static func loadAVAsset(from uri: String, completion: @escaping (AVAsset?, Error?) -> Void) {
    if uri.hasPrefix("ph://") {
      guard let phAsset = fetchPHAsset(from: uri) else {
        completion(nil, MediaToolkitError.invalidInput("PHAsset not found for identifier: \(uri)"))
        return
      }
      let options = PHVideoRequestOptions()
      options.isNetworkAccessAllowed = true
      options.deliveryMode = .highQualityFormat

      PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, audioMix, info in
        if let asset = asset {
          completion(asset, nil)
        } else {
          let err = info?[PHImageErrorKey] as? Error
          completion(nil, err ?? MediaToolkitError.invalidInput("Could not load AVAsset from PhotoKit for: \(uri)"))
        }
      }
    } else {
      let url = resolveURL(from: uri)
      let asset = AVAsset(url: url)
      completion(asset, nil)
    }
  }

  /// Async/await wrapper for loadAVAsset.
  static func loadAVAssetAsync(from uri: String) async throws -> AVAsset {
    return try await withCheckedThrowingContinuation { continuation in
      loadAVAsset(from: uri) { asset, error in
        if let error = error {
          continuation.resume(throwing: error)
        } else if let asset = asset {
          continuation.resume(returning: asset)
        } else {
          continuation.resume(throwing: MediaToolkitError.invalidInput("Cannot load video: \(uri)"))
        }
      }
    }
  }

  /// Loads image data from a URI, resolving ph:// from PhotoKit if needed.
  static func loadImageData(from uri: String) -> Data? {
    if uri.hasPrefix("ph://") {
      guard let phAsset = fetchPHAsset(from: uri) else { return nil }
      let options = PHImageRequestOptions()
      options.isSynchronous = true
      options.isNetworkAccessAllowed = true
      options.deliveryMode = .highQualityFormat
      var imgData: Data?
      PHImageManager.default().requestImageDataAndOrientation(for: phAsset, options: options) { data, _, _, _ in
        imgData = data
      }
      return imgData
    } else {
      let path = resolveFilePath(from: uri)
      return try? Data(contentsOf: URL(fileURLWithPath: path))
    }
  }
}
