import Foundation
import UIKit
import CoreGraphics
import ImageIO
import MobileCoreServices
import UniformTypeIdentifiers

/// Handles image crop and compress on iOS using CGImage + UIKit.
/// All operations are synchronous and must be called from a background queue.
@objc
class ImageProcessor: NSObject {

  // ─── CROP ────────────────────────────────────────────────────────────────

  /// Crops the image at `uri` by a relative region (x,y,w,h all 0–1).
  /// - Returns: absolute output file path
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
    outputPath: String?
  ) throws -> [String: Any] {
    guard let image = loadImage(from: uri) else {
      throw MediaToolkitError.invalidInput("Cannot load image at: \(uri)")
    }

    let normalised = normaliseOrientation(image)
    let resized = resizeIfNeeded(normalised, maxWidth: maxWidth, maxHeight: maxHeight)

    let q = CGFloat(max(0, min(100, quality))) / 100.0
    let ext: String
    let data: Data?
    let mime: String

    switch format {
    case "png":
      ext = "png"; mime = "image/png"
      data = resized.pngData()
    case "webp":
      // iOS doesn't have native WebP encode — fall back to JPEG
      ext = "jpg"; mime = "image/jpeg"
      data = resized.jpegData(compressionQuality: q)
    default:
      ext = "jpg"; mime = "image/jpeg"
      data = resized.jpegData(compressionQuality: q)
    }

    guard let imageData = data else {
      throw MediaToolkitError.processingFailed("Could not encode image")
    }

    let out = outputPath ?? tempPath(ext: ext)
    try imageData.write(to: URL(fileURLWithPath: out))

    return result(path: out, image: resized, mime: mime)
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  private static func loadImage(from uri: String) -> UIImage? {
    let path = uri.hasPrefix("file://")
      ? String(uri.dropFirst(7))
      : uri
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
    let mw = maxWidth > 0 ? CGFloat(maxWidth) : w
    let mh = maxHeight > 0 ? CGFloat(maxHeight) : h
    if w <= mw && h <= mh { return image }

    let ratio = min(mw / w, mh / h)
    let newSize = CGSize(width: w * ratio, height: h * ratio)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: newSize))
    }
  }

  static func tempPath(ext: String) -> String {
    let name = UUID().uuidString + "." + ext
    return (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
  }

  private static func result(path: String, image: UIImage, mime: String) -> [String: Any] {
    let size = (try? Data(contentsOf: URL(fileURLWithPath: path)).count) ?? 0
    return [
      "uri": "file://" + path,
      "size": size,
      "width": Int(image.size.width * image.scale),
      "height": Int(image.size.height * image.scale),
      "duration": 0,
      "mime": mime,
    ]
  }
}
