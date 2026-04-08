import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import UIKit

/// Handles video trim, crop, compress on iOS using AVFoundation.
/// All operations are async (AVAssetExportSession) and call back via progressHandler.
@objc
class VideoProcessor: NSObject {

  typealias ProgressHandler = (_ progress: Float) -> Void
  typealias Completion = (_ result: [String: Any]?, _ error: Error?) -> Void

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
  /// Faster and preserves quality vs running trimVideo + cropVideo sequentially.
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

    // Build crop composition
    let naturalSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let fw = abs(naturalSize.width), fh = abs(naturalSize.height)
    let cropX = CGFloat(x) * fw, cropY = CGFloat(y) * fh
    let cropW = CGFloat(width) * fw, cropH = CGFloat(height) * fh

    let transform = CGAffineTransform(translationX: -cropX, y: -cropY)
      .concatenating(videoTrack.preferredTransform)

    let composition = AVMutableVideoComposition()
    composition.renderSize = CGSize(width: cropW, height: cropH)
    composition.frameDuration = CMTime(
      value: 1,
      timescale: CMTimeScale(videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 30)
    )

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    layerInstruction.setTransform(transform, at: .zero)
    instruction.layerInstructions = [layerInstruction]
    composition.instructions = [instruction]

    // Use Medium preset — crop always requires re-encode; Medium is ~2x faster than Highest
    guard let session = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetMediumQuality
    ) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session")); return
    }

    // Apply BOTH time range (trim) AND video composition (crop) in one session
    let start = CMTime(seconds: startMs / 1000.0, preferredTimescale: 600)
    let end   = CMTime(seconds: endMs   / 1000.0, preferredTimescale: 600)
    session.outputFileType    = .mp4
    session.outputURL         = outURL
    session.videoComposition  = composition
    session.timeRange         = CMTimeRange(start: start, end: end)

    pollProgress(session: session, onProgress: onProgress)
    session.exportAsynchronously {
      switch session.status {
      case .completed:
        completion(videoResult(path: out, asset: asset, trimmed: endMs - startMs), nil)
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

    // Build composition
    guard
      let videoTrack = asset.tracks(withMediaType: .video).first
    else {
      completion(nil, MediaToolkitError.processingFailed("No video track"))
      return
    }

    let naturalSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let fw = abs(naturalSize.width)
    let fh = abs(naturalSize.height)

    let cropX  = CGFloat(x) * fw
    let cropY  = CGFloat(y) * fh
    let cropW  = CGFloat(width) * fw
    let cropH  = CGFloat(height) * fh

    // Translate so crop region starts at origin
    let transform = CGAffineTransform(translationX: -cropX, y: -cropY)
      .concatenating(videoTrack.preferredTransform)

    let composition = AVMutableVideoComposition()
    composition.renderSize = CGSize(width: cropW, height: cropH)
    composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 30))

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    layerInstruction.setTransform(transform, at: .zero)
    instruction.layerInstructions = [layerInstruction]
    composition.instructions = [instruction]

    // MediumQuality is ~2x faster than HighestQuality for crop re-encodes
    guard let session = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetMediumQuality
    ) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session"))
      return
    }

    session.outputFileType       = .mp4
    session.outputURL            = outURL
    session.videoComposition     = composition

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

    var preset: String
    if targetSizeInMB > 0 {
      // Smart Compress always attempts HEVC for 50% better compression matching target size
      preset = AVAssetExportPresetHEVCHighestQuality
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

    // Bitrate strictly follows Export Preset.
    // Quality mapping was handled in `preset` resolution above.

    // Build a video composition to apply maxWidth + adaptive resolution constraints
    if let videoTrack = exportAsset.tracks(withMediaType: .video).first {
      let ns = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
      var fw = abs(ns.width)
      var fh = abs(ns.height)
      
      if targetSizeInMB > 0 {
          let durationSecs = asset.duration.seconds
          if durationSecs > 0 {
              var targetBitrate = (targetSizeInMB * 1024 * 1024 * 8) / durationSecs
              if muteAudio == false { targetBitrate -= 96_000 } // audio reserve

              // Optimal resolution heuristic
              let optimalRes: CGFloat
              if targetBitrate > 3_000_000 { optimalRes = 1080 }
              else if targetBitrate > 1_500_000 { optimalRes = 720 }
              else if targetBitrate > 800_000 { optimalRes = 540 }
              else { optimalRes = 480 }
              
              let finalResTarget = max(optimalRes, CGFloat(minResolution > 0 ? minResolution : 480))
              let shortEdge = min(fw, fh)
              
              if shortEdge > finalResTarget {
                  let scale = finalResTarget / shortEdge
                  fw *= scale
                  fh *= scale
              }
          }
      }

      if maxWidth > 0 && fw > CGFloat(maxWidth) {
        fh = fh * CGFloat(maxWidth) / fw
        fw = CGFloat(maxWidth)
      }
      
      let comp = AVMutableVideoComposition(propertiesOf: exportAsset)
      comp.renderSize = CGSize(width: fw, height: fh)
      session.videoComposition = comp
    }

    if targetSizeInMB > 0 {
        // AVAssetExportSession accepts fileLengthLimit for multi-pass matching
        session.fileLengthLimit = Int64(targetSizeInMB * 1024 * 1024)
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

  private static func videoResult(path: String, asset: AVAsset, trimmed: Double) -> [String: Any] {
    let fileSize = (try? Data(contentsOf: URL(fileURLWithPath: path)).count) ?? 0
    var w = 0; var h = 0
    if let track = asset.tracks(withMediaType: .video).first {
      let ns = track.naturalSize.applying(track.preferredTransform)
      w = Int(abs(ns.width))
      h = Int(abs(ns.height))
    }
    return [
      "uri":      "file://" + path,
      "size":     fileSize,
      "width":    w,
      "height":   h,
      "duration": Int(trimmed),
      "mime":     "video/mp4",
    ]
  }
}
