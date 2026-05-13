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

  // ─── PROCESS (Crop + Flip + Rotate) ──────────────────────────────────────

  @objc
  static func processImage(
    uri: String,
    cropX: Double,
    cropY: Double,
    cropW: Double,
    cropH: Double,
    flip: String?,
    rotation: Double,
    cornerRadius: Double,
    outputPath: String?
  ) throws -> [String: Any] {
    guard let image = loadImage(from: uri) else {
      throw MediaToolkitError.invalidInput("Cannot load image at: \(uri)")
    }
    let normalised = normaliseOrientation(image)
    var finalImage = normalised

    // 1. Crop
    if cropW > 0 && cropH > 0 {
      let iw = finalImage.size.width
      let ih = finalImage.size.height
      let cropRect = CGRect(x: CGFloat(cropX) * iw, y: CGFloat(cropY) * ih, width: CGFloat(cropW) * iw, height: CGFloat(cropH) * ih)
      if let cgCropped = finalImage.cgImage?.cropping(to: cropRect) {
          finalImage = UIImage(cgImage: cgCropped)
      }
    }

    // 2. Rotate
    if rotation != 0 {
      let radians = CGFloat(rotation) * .pi / 180.0
      var newSize = CGRect(origin: .zero, size: finalImage.size)
          .applying(CGAffineTransform(rotationAngle: radians)).size
      newSize.width = floor(newSize.width)
      newSize.height = floor(newSize.height)

      UIGraphicsBeginImageContextWithOptions(newSize, false, finalImage.scale)
      if let context = UIGraphicsGetCurrentContext() {
          context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
          context.rotate(by: radians)
          finalImage.draw(in: CGRect(x: -finalImage.size.width / 2, y: -finalImage.size.height / 2, width: finalImage.size.width, height: finalImage.size.height))
          finalImage = UIGraphicsGetImageFromCurrentImageContext() ?? finalImage
      }
      UIGraphicsEndImageContext()
    }

    // 3. Flip
    if let flipDir = flip, flipDir == "horizontal" || flipDir == "vertical" {
      let size = finalImage.size
      UIGraphicsBeginImageContextWithOptions(size, false, finalImage.scale)
      if let context = UIGraphicsGetCurrentContext() {
          if flipDir == "horizontal" {
              context.translateBy(x: size.width, y: 0)
              context.scaleBy(x: -1.0, y: 1.0)
          } else {
              context.translateBy(x: 0, y: size.height)
              context.scaleBy(x: 1.0, y: -1.0)
          }
          finalImage.draw(in: CGRect(origin: .zero, size: size))
          finalImage = UIGraphicsGetImageFromCurrentImageContext() ?? finalImage
      }
      UIGraphicsEndImageContext()
    }

    // 4. Corner Radius
    if cornerRadius != 0 {
      finalImage = applyCornerRadius(to: finalImage, radius: cornerRadius)
    }

    let hasAlpha = cornerRadius != 0
    let ext = hasAlpha ? "png" : "jpg"
    let mime = hasAlpha ? "image/png" : "image/jpeg"
    let out = outputPath ?? tempPath(ext: ext)
    
    let data = hasAlpha ? (finalImage.pngData() ?? Data()) : (finalImage.jpegData(compressionQuality: 0.9) ?? Data())
    try data.write(to: URL(fileURLWithPath: out))

    return result(path: out, image: finalImage, mime: mime)
  }

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
    cornerRadius: Double,
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

    var cropped = UIImage(cgImage: cgCropped)
    if cornerRadius != 0 {
      cropped = applyCornerRadius(to: cropped, radius: cornerRadius)
    }
    
    let hasAlpha = cornerRadius != 0
    let ext = hasAlpha ? "png" : "jpg"
    let mime = hasAlpha ? "image/png" : "image/jpeg"
    let out = outputPath ?? tempPath(ext: ext)
    
    let data = hasAlpha ? (cropped.pngData() ?? Data()) : (cropped.jpegData(compressionQuality: 0.9) ?? Data())
    try data.write(to: URL(fileURLWithPath: out))

    return result(path: out, image: cropped, mime: mime)
  }

  // ─── ROTATE ──────────────────────────────────────────────────────────────

  @objc
  static func rotateImage(
    uri: String,
    degrees: Double,
    cornerRadius: Double,
    outputPath: String?
  ) throws -> [String: Any] {
    guard let image = loadImage(from: uri) else {
      throw MediaToolkitError.invalidInput("Cannot load image at: \(uri)")
    }
    let normalised = normaliseOrientation(image)
    
    let radians = CGFloat(degrees) * .pi / 180.0
    var newSize = CGRect(origin: .zero, size: normalised.size)
        .applying(CGAffineTransform(rotationAngle: radians)).size
    newSize.width = floor(newSize.width)
    newSize.height = floor(newSize.height)

    UIGraphicsBeginImageContextWithOptions(newSize, false, normalised.scale)
    guard let context = UIGraphicsGetCurrentContext() else {
      throw MediaToolkitError.processingFailed("Context failed")
    }
    context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
    context.rotate(by: radians)
    normalised.draw(in: CGRect(x: -normalised.size.width / 2, y: -normalised.size.height / 2, width: normalised.size.width, height: normalised.size.height))
    var rotated = UIGraphicsGetImageFromCurrentImageContext() ?? normalised
    UIGraphicsEndImageContext()

    if cornerRadius != 0 {
      rotated = applyCornerRadius(to: rotated, radius: cornerRadius)
    }

    let hasAlpha = cornerRadius != 0
    let ext = hasAlpha ? "png" : "jpg"
    let mime = hasAlpha ? "image/png" : "image/jpeg"
    let out = outputPath ?? tempPath(ext: ext)
    
    let data = hasAlpha ? (rotated.pngData() ?? Data()) : (rotated.jpegData(compressionQuality: 0.9) ?? Data())
    try data.write(to: URL(fileURLWithPath: out))

    return result(path: out, image: rotated, mime: mime)
  }

  // ─── FLIP ────────────────────────────────────────────────────────────────

  @objc
  static func flipImage(
    uri: String,
    direction: String,
    cornerRadius: Double,
    outputPath: String?
  ) throws -> [String: Any] {
    guard let image = loadImage(from: uri) else {
      throw MediaToolkitError.invalidInput("Cannot load image at: \(uri)")
    }
    let normalised = normaliseOrientation(image)
    let size = normalised.size
    
    UIGraphicsBeginImageContextWithOptions(size, false, normalised.scale)
    guard let context = UIGraphicsGetCurrentContext() else {
      throw MediaToolkitError.processingFailed("Context failed")
    }
    
    if direction == "horizontal" {
      context.translateBy(x: size.width, y: 0)
      context.scaleBy(x: -1.0, y: 1.0)
    } else { // vertical
      context.translateBy(x: 0, y: size.height)
      context.scaleBy(x: 1.0, y: -1.0)
    }
    
    normalised.draw(in: CGRect(origin: .zero, size: size))
    var flipped = UIGraphicsGetImageFromCurrentImageContext() ?? normalised
    UIGraphicsEndImageContext()

    if cornerRadius != 0 {
      flipped = applyCornerRadius(to: flipped, radius: cornerRadius)
    }

    let hasAlpha = cornerRadius != 0
    let ext = hasAlpha ? "png" : "jpg"
    let mime = hasAlpha ? "image/png" : "image/jpeg"
    let out = outputPath ?? tempPath(ext: ext)
    
    let data = hasAlpha ? (flipped.pngData() ?? Data()) : (flipped.jpegData(compressionQuality: 0.9) ?? Data())
    try data.write(to: URL(fileURLWithPath: out))

    return result(path: out, image: flipped, mime: mime)
  }

  // ─── COMPRESS ────────────────────────────────────────────────────────────

  @objc
  static func compressImage(
    uri: String,
    quality: Double,
    maxWidth: Double,
    maxHeight: Double,
    format: String,
    cornerRadius: Double,
    outputPath: String?
  ) throws -> [String: Any] {
    let path = uri.hasPrefix("file://") ? String(uri.dropFirst(7)) : uri
    let url = URL(fileURLWithPath: path)
    
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw MediaToolkitError.invalidInput("Cannot load image source at: \(uri)")
    }

    // Determine max pixel size for downsampling (memory optimization)
    let maxPx = max(maxWidth, maxHeight)
    let downsampleOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true, // Auto-fixes EXIF rotation!
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPx > 0 ? maxPx : 99999
    ]
    
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
      throw MediaToolkitError.processingFailed("Could not downsample or decode image.")
    }

    var resized = UIImage(cgImage: cgImage)
    if cornerRadius != 0 {
      resized = applyCornerRadius(to: resized, radius: cornerRadius)
    }

    let q = CGFloat(max(0, min(100, quality))) / 100.0
    let ext: String
    let data: Data?
    let mime: String
    
    let forcePng = cornerRadius != 0

    if forcePng || format == "png" {
      ext = "png"; mime = "image/png"
      data = resized.pngData()
    } else if format == "webp" {
      throw MediaToolkitError.processingFailed(
        "WebP encoding is not supported on iOS. Use \"jpeg\" or \"png\" instead."
      )
    } else {
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

  @objc
  static func splitImage(
    uri: String,
    rows: Double,
    columns: Double,
    format: String?,
    quality: Double,
    outputDir: String?,
    prefix: String?
  ) throws -> [[String: Any]] {
    let rowCount = Int(rows)
    let columnCount = Int(columns)
    guard rowCount > 0, columnCount > 0 else {
      throw MediaToolkitError.invalidInput("rows and columns must be greater than 0")
    }

    let path = uri.hasPrefix("file://") ? String(uri.dropFirst(7)) : uri
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw MediaToolkitError.invalidInput("Cannot load image source at: \(uri)")
    }
    guard let image = loadImage(from: uri) else {
      throw MediaToolkitError.invalidInput("Cannot load image at: \(uri)")
    }

    let normalised = normaliseOrientation(image)
    guard let cgImage = normalised.cgImage else {
      throw MediaToolkitError.processingFailed("Could not access CGImage backing store")
    }

    let encoding = resolveSplitEncoding(requestedFormat: format, source: source)
    let directory = try resolveOutputDirectory(outputDir)
    let basePrefix = prefix?.isEmpty == false ? prefix! : "split_\(UUID().uuidString)"
    let clampedQuality = max(0, min(100, quality)) / 100.0
    var results: [[String: Any]] = []

    for row in 0..<rowCount {
      let top = cgImage.height * row / rowCount
      let bottom = cgImage.height * (row + 1) / rowCount
      let tileHeight = max(1, bottom - top)

      for column in 0..<columnCount {
        let left = cgImage.width * column / columnCount
        let right = cgImage.width * (column + 1) / columnCount
        let tileWidth = max(1, right - left)
        let cropRect = CGRect(x: left, y: top, width: tileWidth, height: tileHeight)

        guard let tileCGImage = cgImage.cropping(to: cropRect) else {
          throw MediaToolkitError.processingFailed("Failed to crop split tile at row \(row + 1), column \(column + 1)")
        }

        let tileImage = UIImage(cgImage: tileCGImage, scale: normalised.scale, orientation: .up)
        let fileName = "\(basePrefix)_r\(row + 1)_c\(column + 1).\(encoding.ext)"
        let outputURL = directory.appendingPathComponent(fileName)
        let data = try encodeSplitImage(tileImage, encoding: encoding, quality: clampedQuality)
        try data.write(to: outputURL)
        results.append(result(path: outputURL.path, image: tileImage, mime: encoding.mime))
      }
    }

    return results
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

  private struct SplitImageEncoding {
    let ext: String
    let mime: String
    let kind: String
  }

  private static func resolveSplitEncoding(
    requestedFormat: String?,
    source: CGImageSource
  ) -> SplitImageEncoding {
    let normalized = requestedFormat?.lowercased()
    if normalized == "png" {
      return SplitImageEncoding(ext: "png", mime: "image/png", kind: "png")
    }
    if normalized == "jpeg" || normalized == "jpg" {
      return SplitImageEncoding(ext: "jpg", mime: "image/jpeg", kind: "jpeg")
    }
    if normalized == "webp" {
      return SplitImageEncoding(ext: "png", mime: "image/png", kind: "png")
    }

    let sourceType = CGImageSourceGetType(source) as String?
    if let sourceType, let utType = UTType(sourceType) {
      if utType.conforms(to: .png) {
        return SplitImageEncoding(ext: "png", mime: "image/png", kind: "png")
      }
      if utType.conforms(to: .jpeg) {
        return SplitImageEncoding(ext: "jpg", mime: "image/jpeg", kind: "jpeg")
      }
    }

    return SplitImageEncoding(ext: "jpg", mime: "image/jpeg", kind: "jpeg")
  }

  private static func resolveOutputDirectory(_ outputDir: String?) throws -> URL {
    if let outputDir, !outputDir.isEmpty {
      let url = URL(fileURLWithPath: outputDir, isDirectory: true)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    }

    let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private static func encodeSplitImage(
    _ image: UIImage,
    encoding: SplitImageEncoding,
    quality: Double
  ) throws -> Data {
    switch encoding.kind {
    case "png":
      if let data = image.pngData() {
        return data
      }
    default:
      if let data = image.jpegData(compressionQuality: quality) {
        return data
      }
    }

    throw MediaToolkitError.processingFailed("Could not encode split image")
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

  private static func applyCornerRadius(to image: UIImage, radius: Double) -> UIImage {
    guard radius != 0 else { return image }
    var actualRadius = CGFloat(radius)
    if radius < 0 {
      let percent = min(abs(CGFloat(radius)), 100.0) / 100.0
      let minDimension = min(image.size.width, image.size.height)
      actualRadius = (minDimension / 2.0) * percent
    }
    let rect = CGRect(origin: .zero, size: image.size)
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    UIBezierPath(roundedRect: rect, cornerRadius: actualRadius).addClip()
    image.draw(in: rect)
    let rounded = UIGraphicsGetImageFromCurrentImageContext() ?? image
    UIGraphicsEndImageContext()
    return rounded
  }
}
