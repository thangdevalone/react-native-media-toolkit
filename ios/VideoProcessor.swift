import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

/// Handles video trim, crop, compress on iOS using AVFoundation.
/// All operations are async (AVAssetExportSession) and call back via progressHandler.
@objc
class VideoProcessor: NSObject {

  typealias ProgressHandler = (_ progress: Float) -> Void
  typealias Completion = (_ result: [String: Any]?, _ error: Error?) -> Void
  private static let maxGifTotalPixels = 40_000_000.0

  // ─── TRIM ────────────────────────────────────────────────────────────────

  @objc
  static func trimVideo(
    uri: String,
    startMs: Double,
    endMs: Double,
    outputPath: String?,
    onProgress: @escaping ProgressHandler,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)")
      )
      return
    }

    let out = outputPath ?? tempPath(ext: "mp4")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)

    // AVAssetExportPresetPassthrough = NO re-encode.
    // Copies the compressed bitstream as-is, cuts at nearest keyframe.
    // Trim time: ~30s -> < 1s. Quality: identical (zero decode/re-encode loss).
    guard let session = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetPassthrough
    ) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session"))
      return
    }

    let start = CMTime(seconds: startMs / 1000.0, preferredTimescale: 600)
    let end   = CMTime(seconds: endMs   / 1000.0, preferredTimescale: 600)
    session.outputFileType = .mp4
    session.outputURL      = outURL
    session.timeRange      = CMTimeRange(start: start, end: end)

    pollProgress(session: session, onProgress: onProgress)

    session.exportAsynchronously {
      switch session.status {
      case .completed:
        completion(videoResult(path: out, asset: asset, trimmed: (endMs - startMs)), nil)
      default:
        completion(nil, session.error ?? MediaToolkitError.processingFailed("Export failed"))
      }
    }
  }

  // ─── TRIM + CROP (single pass) ───────────────────────────────────────────

  /// Trim to [startMs, endMs] AND crop to [x,y,w,h] in ONE encode pass.
  /// Uses CIFilter pipeline which automatically handles video rotation.
  @objc
  static func trimAndCropVideo(
    uri: String,
    startMs: Double,
    endMs: Double,
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    outputPath: String?,
    onProgress: @escaping ProgressHandler,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)")); return
    }
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      completion(nil, MediaToolkitError.processingFailed("No video track")); return
    }

    let out = outputPath ?? tempPath(ext: "mp4")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)

    // Display dimensions (rotation-corrected)
    let tfSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let fw = abs(tfSize.width), fh = abs(tfSize.height)
    let cropX = CGFloat(x) * fw, cropY = CGFloat(y) * fh
    let cropW = CGFloat(width) * fw, cropH = CGFloat(height) * fh

    NSLog("[MediaToolkit] trimAndCrop: naturalSize=%@, transform=%@, display=%.0fx%.0f, crop=(%.0f,%.0f,%.0f,%.0f)",
          NSCoder.string(for: videoTrack.naturalSize), NSCoder.string(for: videoTrack.preferredTransform),
          fw, fh, cropX, cropY, cropW, cropH)

    // ── Build AVMutableComposition ──────────────────────────────────────
    let mixComposition = AVMutableComposition()

    guard let compVideoTrack = mixComposition.addMutableTrack(
      withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create composition video track")); return
    }
    do {
      try compVideoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: asset.duration),
        of: videoTrack, at: .zero
      )
    } catch {
      completion(nil, MediaToolkitError.processingFailed("Failed to insert video track: \(error.localizedDescription)")); return
    }
    // Preserve rotation so CIFilter handler receives display-oriented frames
    compVideoTrack.preferredTransform = videoTrack.preferredTransform

    // Copy audio track
    if let audioTrack = asset.tracks(withMediaType: .audio).first,
       let compAudioTrack = mixComposition.addMutableTrack(
         withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
       ) {
      try? compAudioTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: asset.duration),
        of: audioTrack, at: .zero
      )
    }

    // ── Video composition using CIFilter (rotation handled automatically) ──
    // sourceImage arrives already in display orientation (preferredTransform applied)
    // CIImage uses bottom-left origin; our crop coords use top-left origin
    let videoComp = AVMutableVideoComposition(asset: mixComposition, applyingCIFiltersWithHandler: { request in
      let ciRect = CGRect(
        x: cropX,
        y: fh - cropY - cropH,   // flip Y: top-left → bottom-left origin
        width: cropW,
        height: cropH
      )
      let cropped = request.sourceImage
        .cropped(to: ciRect)
        .transformed(by: CGAffineTransform(translationX: -ciRect.origin.x, y: -ciRect.origin.y))
      request.finish(with: cropped, context: nil)
    })
    videoComp.renderSize = CGSize(width: cropW, height: cropH)

    // ── Export ─────────────────────────────────────────────────────────────
    guard let session = AVAssetExportSession(
      asset: mixComposition,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session")); return
    }

    let start = CMTime(seconds: startMs / 1000.0, preferredTimescale: 600)
    let end   = CMTime(seconds: endMs   / 1000.0, preferredTimescale: 600)
    session.outputFileType    = .mp4
    session.outputURL         = outURL
    session.videoComposition  = videoComp
    session.timeRange         = CMTimeRange(start: start, end: end)

    pollProgress(session: session, onProgress: onProgress)
    session.exportAsynchronously {
      switch session.status {
      case .completed:
        completion(videoResult(path: out, asset: asset, trimmed: endMs - startMs), nil)
      default:
        NSLog("[MediaToolkit] trimAndCrop export failed: %@", session.error?.localizedDescription ?? "unknown")
        completion(nil, session.error ?? MediaToolkitError.processingFailed("Export failed"))
      }
    }
  }

  // ─── PROCESS (Trim + Crop + Flip + Rotate) ───────────────────────────────

  @objc
  static func processVideo(
    uri: String,
    startMs: Double,
    endMs: Double,
    cropX: Double,
    cropY: Double,
    cropW: Double,
    cropH: Double,
    flip: String?,
    rotation: Double,
    outputPath: String?,
    onProgress: @escaping ProgressHandler,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)")); return
    }
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      completion(nil, MediaToolkitError.processingFailed("No video track")); return
    }

    let out = outputPath ?? tempPath(ext: "mp4")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)

    let mixComposition = AVMutableComposition()
    guard let compVideoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create track")); return
    }
    try? compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
    compVideoTrack.preferredTransform = videoTrack.preferredTransform

    if let audioTrack = asset.tracks(withMediaType: .audio).first,
       let compAudioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try? compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
    }

    let tfSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let fw = abs(tfSize.width)
    let fh = abs(tfSize.height)
    
    let isCrop = cropW > 0 && cropH > 0
    let cX = CGFloat(cropX) * fw
    let cY = CGFloat(cropY) * fh
    let cW = isCrop ? CGFloat(cropW) * fw : fw
    let cH = isCrop ? CGFloat(cropH) * fh : fh

    let isHorizontal = (flip == "horizontal")
    let isVertical = (flip == "vertical")
    let radians = CGFloat(-rotation) * .pi / 180.0
    
    var finalSize = CGRect(origin: .zero, size: CGSize(width: cW, height: cH))
        .applying(CGAffineTransform(rotationAngle: radians)).size
    finalSize.width = abs(finalSize.width)
    finalSize.height = abs(finalSize.height)

    let videoComp = AVMutableVideoComposition(asset: mixComposition, applyingCIFiltersWithHandler: { request in
      var img = request.sourceImage
      
      if isCrop {
          let ciRect = CGRect(x: cX, y: fh - cY - cH, width: cW, height: cH)
          img = img.cropped(to: ciRect).transformed(by: CGAffineTransform(translationX: -ciRect.origin.x, y: -ciRect.origin.y))
      }
      
      img = img.transformed(by: CGAffineTransform(translationX: -cW/2, y: -cH/2))
      if isHorizontal { img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1)) }
      if isVertical   { img = img.transformed(by: CGAffineTransform(scaleX: 1, y: -1)) }
      if rotation != 0 { img = img.transformed(by: CGAffineTransform(rotationAngle: radians)) }
      img = img.transformed(by: CGAffineTransform(translationX: finalSize.width/2, y: finalSize.height/2))
      
      request.finish(with: img, context: nil)
    })
    videoComp.renderSize = finalSize

    guard let session = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session")); return
    }

    session.outputFileType = .mp4
    session.outputURL = outURL
    session.videoComposition = videoComp
    
    if startMs > 0 || endMs > 0 {
        let start = CMTime(seconds: startMs / 1000.0, preferredTimescale: 600)
        let end   = CMTime(seconds: endMs   / 1000.0, preferredTimescale: 600)
        session.timeRange = CMTimeRange(start: start, end: end)
    }

    pollProgress(session: session, onProgress: onProgress)
    session.exportAsynchronously {
      switch session.status {
      case .completed:
        let duration = (endMs > 0 ? endMs - startMs : asset.duration.seconds * 1000)
        completion(videoResult(path: out, asset: asset, trimmed: duration), nil)
      default:
        completion(nil, session.error ?? MediaToolkitError.processingFailed("Export failed"))
      }
    }
  }

  // ─── CROP ────────────────────────────────────────────────────────────────

  @objc
  static func cropVideo(
    uri: String,
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    outputPath: String?,
    onProgress: @escaping ProgressHandler,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)"))
      return
    }

    let out = outputPath ?? tempPath(ext: "mp4")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)

    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      completion(nil, MediaToolkitError.processingFailed("No video track"))
      return
    }

    // Display dimensions (rotation-corrected)
    let tfSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let fw = abs(tfSize.width)
    let fh = abs(tfSize.height)

    let cropX  = CGFloat(x) * fw
    let cropY  = CGFloat(y) * fh
    let cropW  = CGFloat(width) * fw
    let cropH  = CGFloat(height) * fh

    NSLog("[MediaToolkit] crop: naturalSize=%@, preferredTransform=%@, display=%.0fx%.0f, crop=(%.0f,%.0f,%.0f,%.0f)",
          NSCoder.string(for: videoTrack.naturalSize), NSCoder.string(for: videoTrack.preferredTransform),
          fw, fh, cropX, cropY, cropW, cropH)

    // ── Build AVMutableComposition ──────────────────────────────────────
    let mixComposition = AVMutableComposition()

    guard let compVideoTrack = mixComposition.addMutableTrack(
      withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create composition video track"))
      return
    }
    do {
      try compVideoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: asset.duration),
        of: videoTrack, at: .zero
      )
    } catch {
      completion(nil, MediaToolkitError.processingFailed("Failed to insert video track: \(error.localizedDescription)"))
      return
    }
    // Preserve rotation so CIFilter handler receives display-oriented frames
    compVideoTrack.preferredTransform = videoTrack.preferredTransform

    // Copy audio track
    if let audioTrack = asset.tracks(withMediaType: .audio).first,
       let compAudioTrack = mixComposition.addMutableTrack(
         withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
       ) {
      try? compAudioTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: asset.duration),
        of: audioTrack, at: .zero
      )
    }

    // ── Video composition using CIFilter (rotation handled automatically) ──
    // sourceImage arrives already in display orientation (preferredTransform applied)
    // CIImage uses bottom-left origin; our crop coords use top-left origin
    let videoComp = AVMutableVideoComposition(asset: mixComposition, applyingCIFiltersWithHandler: { request in
      let ciRect = CGRect(
        x: cropX,
        y: fh - cropY - cropH,   // flip Y: top-left → bottom-left origin
        width: cropW,
        height: cropH
      )
      let cropped = request.sourceImage
        .cropped(to: ciRect)
        .transformed(by: CGAffineTransform(translationX: -ciRect.origin.x, y: -ciRect.origin.y))
      request.finish(with: cropped, context: nil)
    })
    videoComp.renderSize = CGSize(width: cropW, height: cropH)

    // ── Export ─────────────────────────────────────────────────────────────
    guard let session = AVAssetExportSession(
      asset: mixComposition,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session"))
      return
    }

    session.outputFileType       = .mp4
    session.outputURL            = outURL
    session.videoComposition     = videoComp

    pollProgress(session: session, onProgress: onProgress)

    session.exportAsynchronously {
      switch session.status {
      case .completed:
        let durationMs = asset.duration.seconds * 1000
        completion(videoResult(path: out, asset: asset, trimmed: durationMs), nil)
      default:
        NSLog("[MediaToolkit] crop export failed: %@", session.error?.localizedDescription ?? "unknown")
        completion(nil, session.error ?? MediaToolkitError.processingFailed("Export failed"))
      }
    }
  }

  // ─── ROTATE ──────────────────────────────────────────────────────────────

  @objc
  static func rotateVideo(
    uri: String,
    degrees: Double,
    outputPath: String?,
    onProgress: @escaping ProgressHandler,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)")); return
    }
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      completion(nil, MediaToolkitError.processingFailed("No video track")); return
    }
    let out = outputPath ?? tempPath(ext: "mp4")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)

    let mixComposition = AVMutableComposition()
    guard let compVideoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create track")); return
    }
    try? compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
    compVideoTrack.preferredTransform = videoTrack.preferredTransform

    if let audioTrack = asset.tracks(withMediaType: .audio).first,
       let compAudioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try? compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
    }

    let tfSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let fw = abs(tfSize.width)
    let fh = abs(tfSize.height)
    
    // In CIImage, rotation is counter-clockwise. To match UI clockwise we negate
    let radians = CGFloat(-degrees) * .pi / 180.0
    var newSize = CGRect(origin: .zero, size: CGSize(width: fw, height: fh))
        .applying(CGAffineTransform(rotationAngle: radians)).size
    newSize.width = abs(newSize.width)
    newSize.height = abs(newSize.height)

    let videoComp = AVMutableVideoComposition(asset: mixComposition, applyingCIFiltersWithHandler: { request in
        let source = request.sourceImage
        var tx = source.transformed(by: CGAffineTransform(translationX: -fw/2, y: -fh/2))
        tx = tx.transformed(by: CGAffineTransform(rotationAngle: radians))
        tx = tx.transformed(by: CGAffineTransform(translationX: newSize.width/2, y: newSize.height/2))
        request.finish(with: tx, context: nil)
    })
    videoComp.renderSize = newSize

    guard let session = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session")); return
    }
    session.outputFileType = .mp4
    session.outputURL = outURL
    session.videoComposition = videoComp
    pollProgress(session: session, onProgress: onProgress)
    session.exportAsynchronously {
      switch session.status {
      case .completed:
        completion(videoResult(path: out, asset: asset, trimmed: asset.duration.seconds * 1000), nil)
      default:
        completion(nil, session.error ?? MediaToolkitError.processingFailed("Export failed"))
      }
    }
  }

  // ─── FLIP ────────────────────────────────────────────────────────────────

  @objc
  static func flipVideo(
    uri: String,
    direction: String,
    outputPath: String?,
    onProgress: @escaping ProgressHandler,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)")); return
    }
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      completion(nil, MediaToolkitError.processingFailed("No video track")); return
    }
    let out = outputPath ?? tempPath(ext: "mp4")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)

    let mixComposition = AVMutableComposition()
    guard let compVideoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create track")); return
    }
    try? compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
    compVideoTrack.preferredTransform = videoTrack.preferredTransform

    if let audioTrack = asset.tracks(withMediaType: .audio).first,
       let compAudioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try? compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
    }

    let tfSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let fw = abs(tfSize.width)
    let fh = abs(tfSize.height)
    let isHorizontal = (direction == "horizontal")

    let videoComp = AVMutableVideoComposition(asset: mixComposition, applyingCIFiltersWithHandler: { request in
        let source = request.sourceImage
        var tx = source.transformed(by: CGAffineTransform(translationX: -fw/2, y: -fh/2))
        if isHorizontal {
            tx = tx.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        } else {
            tx = tx.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
        }
        tx = tx.transformed(by: CGAffineTransform(translationX: fw/2, y: fh/2))
        request.finish(with: tx, context: nil)
    })
    videoComp.renderSize = CGSize(width: fw, height: fh)

    guard let session = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session")); return
    }
    session.outputFileType = .mp4
    session.outputURL = outURL
    session.videoComposition = videoComp
    pollProgress(session: session, onProgress: onProgress)
    session.exportAsynchronously {
      switch session.status {
      case .completed:
        completion(videoResult(path: out, asset: asset, trimmed: asset.duration.seconds * 1000), nil)
      default:
        completion(nil, session.error ?? MediaToolkitError.processingFailed("Export failed"))
      }
    }
  }

  // ─── CHANGE SPEED ────────────────────────────────────────────────────────

  @objc
  static func changeVideoSpeed(
    uri: String,
    speed: Double,
    outputPath: String?,
    onProgress: @escaping ProgressHandler,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)")); return
    }
    let out = outputPath ?? tempPath(ext: "mp4")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)

    let mixComposition = AVMutableComposition()
    let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
    
    // Calculate new duration
    let originalDuration = asset.duration
    let newDuration = CMTimeMultiplyByFloat64(originalDuration, multiplier: 1.0 / speed)

    if let videoTrack = asset.tracks(withMediaType: .video).first,
       let compVideoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try? compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
      compVideoTrack.preferredTransform = videoTrack.preferredTransform
      compVideoTrack.scaleTimeRange(timeRange, toDuration: newDuration)
    }

    if let audioTrack = asset.tracks(withMediaType: .audio).first,
       let compAudioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try? compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
      compAudioTrack.scaleTimeRange(timeRange, toDuration: newDuration)
    }

    guard let session = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session")); return
    }
    session.outputFileType = .mp4
    session.outputURL = outURL
    pollProgress(session: session, onProgress: onProgress)
    session.exportAsynchronously {
      switch session.status {
      case .completed:
        completion(videoResult(path: out, asset: mixComposition, trimmed: newDuration.seconds * 1000), nil)
      default:
        completion(nil, session.error ?? MediaToolkitError.processingFailed("Export failed"))
      }
    }
  }

  // ─── EXTRACT AUDIO ───────────────────────────────────────────────────────

  @objc
  static func extractAudio(
    uri: String,
    outputPath: String?,
    onProgress: @escaping ProgressHandler,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)")); return
    }
    let out = outputPath ?? tempPath(ext: "m4a")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)

    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session")); return
    }
    session.outputFileType = .m4a
    session.outputURL = outURL
    pollProgress(session: session, onProgress: onProgress)
    session.exportAsynchronously {
      switch session.status {
      case .completed:
        completion(videoResult(path: out, asset: asset, trimmed: 0, mime: "audio/m4a"), nil)
      default:
        completion(nil, session.error ?? MediaToolkitError.processingFailed("Export failed"))
      }
    }
  }

  // ─── GENERATE PREVIEW (GIF) ──────────────────────────────────────────────

  @objc
  static func generateVideoPreview(
    uri: String,
    fps: Int,
    durationMs: Int,
    maxWidth: Int,
    quality: Int,
    outputPath: String?,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)")); return
    }
    
    let actualDuration = asset.duration.seconds * 1000.0
    let captureDuration = min(actualDuration, Double(durationMs))
    let framesToCapture = Int((captureDuration / 1000.0) * Double(fps))
    let sourceSize = videoDisplaySize(asset: asset)
    
    if framesToCapture <= 0 {
      completion(nil, MediaToolkitError.processingFailed("Video is too short")); return
    }

    let plannedSize = scaledSize(width: sourceSize.width, height: sourceSize.height, maxWidth: Double(maxWidth))
    let totalPixels = plannedSize.width * plannedSize.height * Double(framesToCapture)
    if plannedSize.width > 0, plannedSize.height > 0, totalPixels > maxGifTotalPixels {
      completion(nil, MediaToolkitError.invalidInput("GIF is too large: \(Int(plannedSize.width))x\(Int(plannedSize.height)) x \(framesToCapture) frames. Use maxWidth 320/540/720 or a shorter duration."))
      return
    }

    let out = outputPath ?? tempPath(ext: "gif")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)
    
    guard let destination = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.gif.identifier as CFString, framesToCapture, nil) else {
      completion(nil, MediaToolkitError.processingFailed("Failed to create GIF destination")); return
    }
    
    let loopProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
    CGImageDestinationSetProperties(destination, loopProperties as CFDictionary)
    
    let delayTime = 1.0 / Double(fps)
    let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delayTime]]
    
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    if maxWidth > 0 {
      gen.maximumSize = CGSize(width: CGFloat(maxWidth), height: CGFloat(maxWidth))
    }

    DispatchQueue.global(qos: .userInitiated).async {
      var outWidth = 0.0
      var outHeight = 0.0
      
      for i in 0..<framesToCapture {
        let timeMs = (Double(i) / Double(fps)) * 1000.0
        let cmTime = CMTime(seconds: timeMs / 1000.0, preferredTimescale: 600)
        
        do {
          let cgImage = try gen.copyCGImage(at: cmTime, actualTime: nil)
          // For GIF we don't strictly apply quality 0-100 to standard CGImageDestination,
          // but we can scale dimensions. We already use maximumSize on generator.
          if outWidth == 0 {
             outWidth = Double(cgImage.width)
             outHeight = Double(cgImage.height)
          }
          CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
        } catch {
          // ignore missed frames
        }
      }
      
      if CGImageDestinationFinalize(destination) {
        if outWidth == 0 || outHeight == 0,
           let source = CGImageSourceCreateWithURL(outURL as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
          outWidth = props[kCGImagePropertyPixelWidth as String] as? Double ?? outWidth
          outHeight = props[kCGImagePropertyPixelHeight as String] as? Double ?? outHeight
        }
        if outWidth == 0 || outHeight == 0 {
          let scaled = scaledSize(width: sourceSize.width, height: sourceSize.height, maxWidth: Double(maxWidth))
          outWidth = scaled.width
          outHeight = scaled.height
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: out)[.size] as? Int) ?? 0
        let result: [String: Any] = [
          "uri": "file://" + out,
          "size": fileSize,
          "width": outWidth,
          "height": outHeight,
          "duration": captureDuration,
          "mime": "image/gif"
        ]
        DispatchQueue.main.async { completion(result, nil) }
      } else {
        DispatchQueue.main.async { completion(nil, MediaToolkitError.processingFailed("Failed to finalize GIF")) }
      }
    }
  }

  // ─── COMPRESS ────────────────────────────────────────────────────────────

  @objc
  static func compressVideo(
    uri: String,
    quality: String,
    bitrate: Double,
    targetSizeInMB: Double,
    minResolution: Double,
    maxWidth: Double,
    muteAudio: Bool,
    outputPath: String?,
    onProgress: @escaping ProgressHandler,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)"))
      return
    }

    let out = outputPath ?? tempPath(ext: "mp4")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)

    var preset: String = AVAssetExportPresetMediumQuality
    if targetSizeInMB > 0 {
      let durationSecs = asset.duration.seconds
      if durationSecs > 0 {
          // --- Impossible Compression Rejection Logic ---
          let minRequiredBitrate: Double = 400_000 + (muteAudio ? 0 : 96_000)
          let minRequiredMB = (durationSecs * minRequiredBitrate) / (8.0 * 1024 * 1024)
          if targetSizeInMB < minRequiredMB {
              let reqMBStr = String(format: "%.1f", minRequiredMB)
              completion(nil, MediaToolkitError.invalidInput("Target size (\(targetSizeInMB)MB) is impossible for a \(Int(durationSecs))s video. Minimum required limit is ~\(reqMBStr)MB to prevent corruption."))
              return
          }
          var origSizeMB: Double = 0
          if let url = (asset as? AVURLAsset)?.url, url.isFileURL,
             let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
             let size = attr[.size] as? Int64 {
              origSizeMB = Double(size) / (1024.0 * 1024.0)
          }
          if origSizeMB > 0 && targetSizeInMB < (origSizeMB * 0.05) {
              completion(nil, MediaToolkitError.invalidInput("Target size is too extreme (< 5% of original). The encoder hardware will fail to squeeze it."))
              return
          }
          // ----------------------------------------------

          var targetBitrate = (targetSizeInMB * 1024 * 1024 * 8) / durationSecs
          if !muteAudio { targetBitrate -= 128_000 }
          
          var optimalRes: CGFloat = 480
          if targetBitrate > 3_000_000 { optimalRes = 1080 }
          else if targetBitrate > 1_500_000 { optimalRes = 720 }
          else if targetBitrate > 800_000 { optimalRes = 540 }
          
          let finalRes = minResolution > 0 ? CGFloat(minResolution) : optimalRes
          if finalRes >= 1080 { preset = AVAssetExportPreset1920x1080 }
          else if finalRes >= 720 { preset = AVAssetExportPreset1280x720 }
          else if finalRes >= 540 { preset = AVAssetExportPreset960x540 }
          else { preset = AVAssetExportPreset640x480 }
      } else {
          preset = AVAssetExportPresetHighestQuality
      }
    } else {
      switch quality {
      case "low":    preset = AVAssetExportPresetLowQuality
      case "high":   preset = AVAssetExportPresetHighestQuality
      default:       preset = AVAssetExportPresetMediumQuality
      }
    }

    // When muteAudio is requested, build a composition that only contains the video track.
    // AVAssetExportSession will then produce a file with no audio stream.
    let exportAsset: AVAsset
    if muteAudio && !asset.tracks(withMediaType: .audio).isEmpty {
      let composition = AVMutableComposition()
      if let videoTrack = asset.tracks(withMediaType: .video).first,
         let compVideoTrack = composition.addMutableTrack(
           withMediaType: .video,
           preferredTrackID: kCMPersistentTrackID_Invalid
         ) {
        try? compVideoTrack.insertTimeRange(
          CMTimeRange(start: .zero, duration: asset.duration),
          of: videoTrack,
          at: .zero
        )
        compVideoTrack.preferredTransform = videoTrack.preferredTransform
      }
      // Deliberately NOT adding audio track → silent output
      exportAsset = composition
    } else {
      exportAsset = asset
    }

    guard let session = AVAssetExportSession(asset: exportAsset, presetName: preset) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session"))
      return
    }

    session.outputFileType = .mp4
    session.outputURL      = outURL

    if targetSizeInMB > 0 {
        // AVAssetExportSession accepts fileLengthLimit natively tracking Bitrate
        var fileLimit = Int64(targetSizeInMB * 1024 * 1024 * 0.90) // 10% safety margin for MP4 overhead
        let sourceAsset = (asset as? AVURLAsset) ?? (exportAsset as? AVURLAsset)
        if let url = sourceAsset?.url, url.isFileURL {
            if let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attr[.size] as? Int64, size > 0 {
                // Prevent inflation: cap at original file size if it's already smaller than target
                fileLimit = min(fileLimit, size)
            }
        }
        session.fileLengthLimit = fileLimit
    }

    pollProgress(session: session, onProgress: onProgress)

    session.exportAsynchronously {
      switch session.status {
      case .completed:
        let durationMs = asset.duration.seconds * 1000
        completion(videoResult(path: out, asset: asset, trimmed: durationMs), nil)
      default:
        completion(nil, session.error ?? MediaToolkitError.processingFailed("Export failed"))
      }
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  private static func loadAsset(_ uri: String) -> AVAsset? {
    let path = uri.hasPrefix("file://") ? String(uri.dropFirst(7)) : uri
    let url: URL
    if path.hasPrefix("/") {
      url = URL(fileURLWithPath: path)
    } else if let u = URL(string: uri) {
      url = u
    } else {
      return nil
    }
    let asset = AVAsset(url: url)
    return asset
  }

  private static func pollProgress(session: AVAssetExportSession, onProgress: @escaping ProgressHandler) {
    // AVAssetExportSession.progress is unreliable — often jumps 0→0→...→1.
    // Strategy: blend real progress with a time-based smooth estimate.
    // - Cap estimated progress at 0.92 so we always have room for the real 1.0
    // - Use 80% weight on time-based smooth curve, 20% on real session.progress
    //   (session.progress is kept in the mix so if it IS accurate we follow it)
    let startTime = Date()
    // Optimistic estimate: most operations finish within 8s for typical clips.
    // For longer exports the estimated curve just plateaus near 0.92 which is fine.
    let estimatedDuration: TimeInterval = 8.0

    let timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { t in
      switch session.status {
      case .completed:
        onProgress(1.0)
        t.invalidate()

      case .failed, .cancelled:
        t.invalidate()

      case .exporting, .waiting:
        let elapsed = Date().timeIntervalSince(startTime)
        // Smooth easing curve: fast start, slows near end — never reaches 1.0
        let timeFraction = min(elapsed / estimatedDuration, 1.0)
        let smoothEstimate = Float(1.0 - pow(1.0 - timeFraction, 2.5)) * 0.92

        // Blend: 80% smooth time estimate + 20% real session progress
        let real = session.progress  // 0.0–1.0 from AVFoundation
        let blended = smoothEstimate * 0.8 + real * 0.2

        // Always move forward, never go backward, cap at 0.95 before completion
        onProgress(min(blended, 0.95))

      default:
        break
      }
    }
    RunLoop.main.add(timer, forMode: .common)
  }

  static func tempPath(ext: String) -> String {
    let name = UUID().uuidString + "." + ext
    return (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
  }

  private static func removeIfExists(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  private static func videoResult(path: String, asset: AVAsset, trimmed: Double, mime: String? = nil) -> [String: Any] {
    // Read file size WITHOUT loading entire file into memory
    let fileSize: Int
    if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
       let size = attrs[.size] as? Int {
      fileSize = size
    } else {
      fileSize = 0
    }

    let outAsset = AVURLAsset(url: URL(fileURLWithPath: path))
    var w = 0; var h = 0

    if let track = outAsset.tracks(withMediaType: .video).first {
      let ns = track.naturalSize.applying(track.preferredTransform)
      w = Int(abs(ns.width))
      h = Int(abs(ns.height))
    } else if let track = asset.tracks(withMediaType: .video).first {
      let ns = track.naturalSize.applying(track.preferredTransform)
      w = Int(abs(ns.width))
      h = Int(abs(ns.height))
    }

    // Read ACTUAL duration from the output file (not the trim range parameter)
    let actualDurationMs = Int(outAsset.duration.seconds * 1000)

    return [
      "uri":      "file://" + path,
      "size":     fileSize,
      "width":    w,
      "height":   h,
      "duration": actualDurationMs,
      "mime":     mime ?? "video/mp4",
    ]
  }

  private static func videoDisplaySize(asset: AVAsset) -> (width: Double, height: Double) {
    guard let track = asset.tracks(withMediaType: .video).first else {
      return (0, 0)
    }
    let size = track.naturalSize.applying(track.preferredTransform)
    return (Double(abs(size.width)), Double(abs(size.height)))
  }

  private static func scaledSize(width: Double, height: Double, maxWidth: Double) -> (width: Double, height: Double) {
    guard width > 0, height > 0 else {
      return (0, 0)
    }
    guard maxWidth > 0, width > maxWidth else {
      return (width.rounded(), height.rounded())
    }
    let scale = maxWidth / width
    return (maxWidth.rounded(), (height * scale).rounded())
  }
}
