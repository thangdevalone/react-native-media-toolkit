import Foundation
import UIKit
import CoreGraphics
import ImageIO
import MobileCoreServices
import UniformTypeIdentifiers

/// Handles image crop and compress on iOS using CGImage + UIKit.
/// All operations are synchronous and must be called from a background queue.
///
/// ## targetSizeMB algorithm (binary-search quality)
///   1. Resize to maxWidth/maxHeight if provided (or derive from target size budget).
///   2. If targetSizeMB is set and the initial encode is still too large:
///      - Binary-search the JPEG quality between 1 and the caller's quality cap.
///      - If even quality=1 at current resolution exceeds the target, halve the
///        resolution and retry (clamped to MIN_SCALE to keep the image usable).
///      - Converges in ≤ 10 iterations (log2(100) < 7 iterations for quality,
///        plus ≤ 3 resolution halves).
@objc
class ImageProcessor: NSObject {

  /// Absolute minimum scale vs original dimensions (never go below this)
  private static let MIN_SCALE: Double = 0.1   // ~10% of original → still viewable thumbnail

  // ─── CROP ────────────────────────────────────────────────────────────────

  @objc
  static func cropImage(
    uri: String,
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    outputPath: String?
  ) throws -> [String: Any] {
    guard let image = loadImage(from: uri) else {
      throw MediaToolkitError.invalidInput("Cannot load image at: \(uri)")
    }

    let normalised = normaliseOrientation(image)
    let iw = normalised.size.width
    let ih = normalised.size.height

    let cropRect = CGRect(
      x: CGFloat(x) * iw,
      y: CGFloat(y) * ih,
      width: CGFloat(width) * iw,
      height: CGFloat(height) * ih
    )

    guard let cgCropped = normalised.cgImage?.cropping(to: cropRect) else {
      throw MediaToolkitError.processingFailed("CGImage crop failed")
    }

    let cropped = UIImage(cgImage: cgCropped)
    let out = outputPath ?? tempPath(ext: "jpg")
    let data = cropped.jpegData(compressionQuality: 0.9) ?? Data()
    try data.write(to: URL(fileURLWithPath: out))

    return result(path: out, image: cropped, mime: "image/jpeg")
  }

  // ─── COMPRESS ────────────────────────────────────────────────────────────

  @objc
  static func compressImage(
    uri: String,
    quality: Double,
    maxWidth: Double,
    maxHeight: Double,
    format: String,
    targetSizeMB: Double,
    outputPath: String?
  ) throws -> [String: Any] {
    guard let image = loadImage(from: uri) else {
      throw MediaToolkitError.invalidInput("Cannot load image at: \(uri)")
    }

    let normalised = normaliseOrientation(image)
    var resized = resizeIfNeeded(normalised, maxWidth: maxWidth, maxHeight: maxHeight)

    let ext: String
    let mime: String

    switch format {
    case "png":
      ext = "png"; mime = "image/png"
    case "webp":
      throw MediaToolkitError.processingFailed(
        "WebP encoding is not supported on iOS. Use \"jpeg\" or \"png\" instead."
      )
    default:
      ext = "jpg"; mime = "image/jpeg"
    }

    let out = outputPath ?? tempPath(ext: ext)

    // ── PNG path: no quality dial, targetSizeMB only honoured via resize ──
    if format == "png" {
      // If targetSizeMB set, we can only reduce resolution for PNG (lossless)
      if targetSizeMB > 0 {
        var scale = 1.0
        var pngData = resized.pngData() ?? Data()
        let targetBytes = Int(targetSizeMB * 1_000_000)
        while pngData.count > targetBytes, scale > MIN_SCALE {
          scale = max(scale * 0.7, MIN_SCALE)
          let w = Int(normalised.size.width * CGFloat(scale))
          let h = Int(normalised.size.height * CGFloat(scale))
          resized = resize(normalised, to: CGSize(width: w, height: h))
          pngData = resized.pngData() ?? Data()
        }
        try pngData.write(to: URL(fileURLWithPath: out))
      } else {
        guard let pngData = resized.pngData() else {
          throw MediaToolkitError.processingFailed("Could not encode PNG")
        }
        try pngData.write(to: URL(fileURLWithPath: out))
      }
      return result(path: out, image: resized, mime: "image/png")
    }

    // ── JPEG path: quality dial + optional targetSizeMB binary search ─────
    let maxQuality = CGFloat(max(1, min(100, quality))) / 100.0

    // Fast path: no target size constraint — encode once
    if targetSizeMB <= 0 {
      guard let data = resized.jpegData(compressionQuality: maxQuality) else {
        throw MediaToolkitError.processingFailed("Could not encode image")
      }
      try data.write(to: URL(fileURLWithPath: out))
      return result(path: out, image: resized, mime: mime)
    }

    // Target-size path: estimation-guided binary search
    // ─────────────────────────────────────────────────────────────────────────
    // Why estimation first:
    //   Pure binary search on [0.01, maxQ] always needs log2(range) iterations
    //   regardless of how close the target is. For a 12MP JPEG each iteration
    //   is ~80-150ms, so 8 iterations = ~1.2s wasted time.
    //
    //   JPEG file size scales approximately as: size ≈ K × quality^0.75
    //   (empirically consistent across content types, not perfectly linear).
    //   So: targetQ ≈ maxQ × (targetBytes / maxQBytes)^(1/0.75)
    //                       = maxQ × (ratio)^1.333
    //   This estimate is usually within ±15% of the true answer, letting
    //   us narrow binary search to a tight range and converge in 3-4 iterations.
    //   Total encode calls: 1 (initial check) + 1 (estimate probe) + 4 (narrow search)
    //   vs old: 1 (initial check) + 8 (full search) = 9.
    let targetBytes = Int(targetSizeMB * 1_000_000)

    // Initial check — encode at max quality once, reuse result for estimation
    guard let initialData = resized.jpegData(compressionQuality: maxQuality) else {
      throw MediaToolkitError.processingFailed("Could not encode image")
    }
    if initialData.count <= targetBytes {
      try initialData.write(to: URL(fileURLWithPath: out))
      return result(path: out, image: resized, mime: mime)
    }

    // Estimate quality using the empirical JPEG size/quality relationship
    let sizeRatio = Double(targetBytes) / Double(max(1, initialData.count))
    // Inverse of size ≈ K×q^0.75: q_est = maxQ × ratio^(1/0.75) = ratio^1.333
    let estimatedQ = maxQuality * CGFloat(pow(sizeRatio, 1.333))
    let clampedEst = max(0.01, min(estimatedQ, maxQuality - 0.01))

    // Narrow binary search around the estimate
    // Range: ±40% of estimate, clamped to [0.01, maxQ]
    var loQ = max(0.01, clampedEst * 0.6)
    var hiQ = min(maxQuality, clampedEst * 1.4)
    var bestData = Data()
    var currentResized = resized

    for _ in 0 ..< 5 {   // 5 iterations on narrow range ≈ original 8 on full range
      let midQ = (loQ + hiQ) / 2.0
      if let data = currentResized.jpegData(compressionQuality: midQ) {
        if data.count <= targetBytes {
          loQ = midQ
          bestData = data
        } else {
          hiQ = midQ
        }
      }
    }

    // Extend search left if estimate was too high (image is denser than average)
    if bestData.isEmpty {
      hiQ = clampedEst * 0.6; loQ = 0.01
      for _ in 0 ..< 5 {
        let midQ = (loQ + hiQ) / 2.0
        if let data = currentResized.jpegData(compressionQuality: midQ) {
          if data.count <= targetBytes {
            loQ = midQ
            bestData = data
          } else {
            hiQ = midQ
          }
        }
      }
    }

    // Fallback: scale down resolution (≤ 3 halvings, floor MIN_SCALE)
    if bestData.isEmpty || bestData.count > targetBytes {
      var scale = 1.0
      for _ in 0 ..< 3 {
        scale = max(scale * 0.5, MIN_SCALE)
        let w = max(2, Int(normalised.size.width  * CGFloat(scale)))
        let h = max(2, Int(normalised.size.height * CGFloat(scale)))
        currentResized = resize(normalised, to: CGSize(width: w, height: h))

        // Re-estimate and narrow-search at smaller resolution
        if let smData = currentResized.jpegData(compressionQuality: maxQuality) {
          if smData.count <= targetBytes { bestData = smData; break }
          let r2 = Double(targetBytes) / Double(max(1, smData.count))
          let est2 = maxQuality * CGFloat(pow(r2, 1.333))
          let lo2 = max(0.01, est2 * 0.6); let hi2 = min(maxQuality, est2 * 1.4)
          var lo = lo2, hi = hi2
          for _ in 0 ..< 5 {
            let mid = (lo + hi) / 2.0
            if let d = currentResized.jpegData(compressionQuality: mid) {
              if d.count <= targetBytes { lo = mid; bestData = d } else { hi = mid }
            }
          }
          if !bestData.isEmpty { break }
        }
        if scale <= MIN_SCALE { break }
      }
    }

    if bestData.isEmpty {
      bestData = currentResized.jpegData(compressionQuality: 0.01) ?? Data()
    }

    try bestData.write(to: URL(fileURLWithPath: out))
    return result(path: out, image: currentResized, mime: mime)
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  private static func loadImage(from uri: String) -> UIImage? {
    let path = uri.hasPrefix("file://") ? String(uri.dropFirst(7)) : uri
    return UIImage(contentsOfFile: path)
  }

  /// Normalize EXIF orientation so crop coords are always top-left based
  private static func normaliseOrientation(_ image: UIImage) -> UIImage {
    guard image.imageOrientation != .up else { return image }
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    image.draw(in: CGRect(origin: .zero, size: image.size))
    let normalised = UIGraphicsGetImageFromCurrentImageContext() ?? image
    UIGraphicsEndImageContext()
    return normalised
  }

  private static func resizeIfNeeded(
    _ image: UIImage,
    maxWidth: Double,
    maxHeight: Double
  ) -> UIImage {
    let w = image.size.width
    let h = image.size.height
    let mw = maxWidth  > 0 ? CGFloat(maxWidth)  : w
    let mh = maxHeight > 0 ? CGFloat(maxHeight) : h
    if w <= mw && h <= mh { return image }
    let ratio = min(mw / w, mh / h)
    return resize(image, to: CGSize(width: w * ratio, height: h * ratio))
  }

  private static func resize(_ image: UIImage, to size: CGSize) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  static func tempPath(ext: String) -> String {
    let name = UUID().uuidString + "." + ext
    return (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
  }

  private static func result(path: String, image: UIImage, mime: String) -> [String: Any] {
    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    return [
      "uri":      "file://" + path,
      "size":     size,
      "width":    Int(image.size.width  * image.scale),
      "height":   Int(image.size.height * image.scale),
      "duration": 0,
      "mime":     mime,
    ]
  }
}
