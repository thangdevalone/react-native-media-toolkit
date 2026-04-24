import AVFoundation
import Foundation
import NitroModules
import UIKit

/// Nitro HybridObject implementation for MediaToolkit.
/// Bridges ImageProcessor and VideoProcessor to the JS layer via Nitro's JSI.
class HybridMediaToolkit: HybridMediaToolkitSpec {

  private let queue = DispatchQueue(
    label: "com.mediatoolkit.operations",
    qos: .userInitiated
  )

  // ─── Image ─────────────────────────────────────────────────────────────────

  func cropImage(uri: String, options: CropOptions) throws -> Promise<MediaResult> {
    return Promise.parallel(queue) {
      let raw = try ImageProcessor.cropImage(
        uri: uri,
        x: options.x,
        y: options.y,
        width: options.width,
        height: options.height,
        outputPath: options.outputPath
      )
      return makeMediaResult(raw)
    }
  }

  func compressImage(uri: String, options: CompressImageOptions) throws -> Promise<MediaResult> {
    return Promise.parallel(queue) {
      let raw = try ImageProcessor.compressImage(
        uri: uri,
        quality: options.quality ?? 80,
        maxWidth: options.maxWidth ?? 0,
        maxHeight: options.maxHeight ?? 0,
        format: options.format ?? "jpeg",
        outputPath: options.outputPath
      )
      return makeMediaResult(raw)
    }
  }

  func flipImage(uri: String, options: FlipOptions) throws -> Promise<MediaResult> {
    return Promise.parallel(queue) {
      let raw = try ImageProcessor.flipImage(
        uri: uri,
        direction: options.direction,
        outputPath: options.outputPath
      )
      return makeMediaResult(raw)
    }
  }

  func rotateImage(uri: String, options: RotateOptions) throws -> Promise<MediaResult> {
    return Promise.parallel(queue) {
      let raw = try ImageProcessor.rotateImage(
        uri: uri,
        degrees: options.degrees,
        outputPath: options.outputPath
      )
      return makeMediaResult(raw)
    }
  }

  func processImage(uri: String, options: ProcessImageOptions) throws -> Promise<MediaResult> {
    return Promise.parallel(queue) {
      let raw = try ImageProcessor.processImage(
        uri: uri,
        cropX: options.cropX ?? 0,
        cropY: options.cropY ?? 0,
        cropW: options.cropWidth ?? 0,
        cropH: options.cropHeight ?? 0,
        flip: options.flip,
        rotation: options.rotation ?? 0,
        outputPath: options.outputPath
      )
      return makeMediaResult(raw)
    }
  }

  // ─── Video ──────────────────────────────────────────────────────────────────

  func trimVideo(uri: String, options: TrimOptions) throws -> Promise<MediaResult> {
    return Promise.async {
      try await withCheckedThrowingContinuation { continuation in
        VideoProcessor.trimVideo(
          uri: uri,
          startMs: options.startTime,
          endMs: options.endTime,
          outputPath: options.outputPath,
          onProgress: { _ in },
          completion: { result, error in
            if let error {
              continuation.resume(throwing: error)
            } else if let result {
              continuation.resume(returning: makeMediaResult(result))
            } else {
              continuation.resume(throwing: MediaToolkitError.processingFailed("No result"))
            }
          }
        )
      }
    }
  }

  func cropVideo(uri: String, options: VideoCropOptions) throws -> Promise<MediaResult> {
    return Promise.async {
      try await withCheckedThrowingContinuation { continuation in
        VideoProcessor.cropVideo(
          uri: uri,
          x: options.x,
          y: options.y,
          width: options.width,
          height: options.height,
          outputPath: options.outputPath,
          onProgress: { _ in },
          completion: { result, error in
            if let error {
              continuation.resume(throwing: error)
            } else if let result {
              continuation.resume(returning: makeMediaResult(result))
            } else {
              continuation.resume(throwing: MediaToolkitError.processingFailed("No result"))
            }
          }
        )
      }
    }
  }

  func compressVideo(uri: String, options: CompressVideoOptions) throws -> Promise<MediaResult> {
    return Promise.async {
      try await withCheckedThrowingContinuation { continuation in
        VideoProcessor.compressVideo(
          uri: uri,
          quality: options.quality ?? "medium",
          bitrate: options.bitrate ?? 0,
          targetSizeInMB: options.targetSizeInMB ?? 0,
          minResolution: options.minResolution ?? 720,
          maxWidth: options.width ?? 0,
          muteAudio: options.muteAudio ?? false,
          outputPath: options.outputPath,
          onProgress: { _ in },
          completion: { result, error in
            if let error {
              continuation.resume(throwing: error)
            } else if let result {
              continuation.resume(returning: makeMediaResult(result))
            } else {
              continuation.resume(throwing: MediaToolkitError.processingFailed("No result"))
            }
          }
        )
      }
    }
  }

  func trimAndCropVideo(uri: String, options: TrimAndCropOptions) throws -> Promise<MediaResult> {
    return Promise.async {
      try await withCheckedThrowingContinuation { continuation in
        VideoProcessor.trimAndCropVideo(
          uri: uri,
          startMs: options.startTime,
          endMs: options.endTime,
          x: options.x,
          y: options.y,
          width: options.width,
          height: options.height,
          outputPath: options.outputPath,
          onProgress: { _ in },
          completion: { result, error in
            if let error {
              continuation.resume(throwing: error)
            } else if let result {
              continuation.resume(returning: makeMediaResult(result))
            } else {
              continuation.resume(throwing: MediaToolkitError.processingFailed("No result"))
            }
          }
        )
      }
    }
  }

  func flipVideo(uri: String, options: FlipOptions) throws -> Promise<MediaResult> {
    return Promise.async {
      try await withCheckedThrowingContinuation { continuation in
        VideoProcessor.flipVideo(
          uri: uri,
          direction: options.direction,
          outputPath: options.outputPath,
          onProgress: { _ in },
          completion: { result, error in
            if let error {
              continuation.resume(throwing: error)
            } else if let result {
              continuation.resume(returning: makeMediaResult(result))
            } else {
              continuation.resume(throwing: MediaToolkitError.processingFailed("No result"))
            }
          }
        )
      }
    }
  }

  func rotateVideo(uri: String, options: RotateOptions) throws -> Promise<MediaResult> {
    return Promise.async {
      try await withCheckedThrowingContinuation { continuation in
        VideoProcessor.rotateVideo(
          uri: uri,
          degrees: options.degrees,
          outputPath: options.outputPath,
          onProgress: { _ in },
          completion: { result, error in
            if let error {
              continuation.resume(throwing: error)
            } else if let result {
              continuation.resume(returning: makeMediaResult(result))
            } else {
              continuation.resume(throwing: MediaToolkitError.processingFailed("No result"))
            }
          }
        )
      }
    }
  }

  func processVideo(uri: String, options: ProcessVideoOptions) throws -> Promise<MediaResult> {
    return Promise.async {
      try await withCheckedThrowingContinuation { continuation in
        VideoProcessor.processVideo(
          uri: uri,
          startMs: options.startTime ?? 0,
          endMs: options.endTime ?? 0,
          cropX: options.cropX ?? 0,
          cropY: options.cropY ?? 0,
          cropW: options.cropWidth ?? 0,
          cropH: options.cropHeight ?? 0,
          flip: options.flip,
          rotation: options.rotation ?? 0,
          outputPath: options.outputPath,
          onProgress: { _ in },
          completion: { result, error in
            if let error {
              continuation.resume(throwing: error)
            } else if let result {
              continuation.resume(returning: makeMediaResult(result))
            } else {
              continuation.resume(throwing: MediaToolkitError.processingFailed("No result"))
            }
          }
        )
      }
    }
  }

  func getThumbnail(uri: String, options: ThumbnailOptions?) throws -> Promise<ThumbnailResult> {
    return Promise.parallel(queue) {
      guard let asset = loadAsset(uri) else {
        throw MediaToolkitError.invalidInput("Cannot load video: \(uri)")
      }
      let timeMs  = options?.timeMs  ?? 0
      let quality = options?.quality ?? 80
      let maxW    = options?.maxWidth ?? 0

      let cmTime = CMTime(seconds: timeMs / 1000.0, preferredTimescale: 600)
      let gen = AVAssetImageGenerator(asset: asset)
      gen.appliesPreferredTrackTransform = true
      gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
      gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.1, preferredTimescale: 600)

      let cgImage = try gen.copyCGImage(at: cmTime, actualTime: nil)
      var uiImage = UIImage(cgImage: cgImage)

      // Source video dimensions (rotation-corrected) — from the full-res image BEFORE scaling
      let srcWidth  = Double(uiImage.size.width)
      let srcHeight = Double(uiImage.size.height)

      if maxW > 0 {
        let scale = CGFloat(maxW) / uiImage.size.width
        if scale < 1.0 {
          let newSize = CGSize(width: CGFloat(maxW), height: uiImage.size.height * scale)
          UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
          uiImage.draw(in: CGRect(origin: .zero, size: newSize))
          uiImage = UIGraphicsGetImageFromCurrentImageContext() ?? uiImage
          UIGraphicsEndImageContext()
        }
      }

      let q = max(0, min(100, Int(quality)))
      guard let data = uiImage.jpegData(compressionQuality: CGFloat(q) / 100.0) else {
        throw MediaToolkitError.processingFailed("Failed to encode JPEG thumbnail")
      }

      let outPath = options?.outputPath ?? (NSTemporaryDirectory() + UUID().uuidString + ".jpg")
      let outURL  = URL(fileURLWithPath: outPath)
      try data.write(to: outURL)

      // Source video file size (NOT the thumbnail JPEG size)
      let srcPath = uri.hasPrefix("file://") ? String(uri.dropFirst(7)) : uri
      let srcFileSize: Double
      if let attrs = try? FileManager.default.attributesOfItem(atPath: srcPath),
         let sz = attrs[.size] as? Int {
        srcFileSize = Double(sz)
      } else {
        srcFileSize = Double(data.count) // fallback to thumbnail size
      }

      // Source video duration in milliseconds (actual file duration)
      let srcDurationMs = asset.duration.seconds * 1000.0

      // Return SOURCE VIDEO metadata (dimensions + file size + duration)
      return ThumbnailResult(
        uri:      "file://" + outPath,
        size:     srcFileSize,
        width:    srcWidth,
        height:   srcHeight,
        duration: srcDurationMs
      )
    }
  }
}

// ─── Private helpers ──────────────────────────────────────────────────────────

private func makeMediaResult(_ raw: [String: Any]) -> MediaResult {
  return MediaResult(
    uri:      raw["uri"]      as? String ?? "",
    size:     Double(raw["size"]     as? Int ?? 0),
    width:    Double(raw["width"]    as? Int ?? 0),
    height:   Double(raw["height"]   as? Int ?? 0),
    duration: Double(raw["duration"] as? Int ?? 0),
    mime:     raw["mime"]     as? String ?? ""
  )
}

private func loadAsset(_ uri: String) -> AVAsset? {
  let path = uri.hasPrefix("file://") ? String(uri.dropFirst(7)) : uri
  let url: URL
  if path.hasPrefix("/") {
    url = URL(fileURLWithPath: path)
  } else if let u = URL(string: uri) {
    url = u
  } else {
    return nil
  }
  return AVAsset(url: url)
}
