import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import UIKit
import VideoToolbox

/// Handles video trim, crop, compress on iOS using AVFoundation.
/// All operations are async and call back via progressHandler.
///
/// ## Compress strategy (AVAssetReader + AVAssetWriter)
///   - H.265 (HEVC) preferred → ~40-50% smaller file at same perceived quality
///   - Hardware VideoToolbox encoder on all A9+ / Apple Silicon chips (near-realtime)
///   - Exact bitrate control via AVVideoAverageBitRateKey
///   - Falls back to H.264 when HEVC is not available
///
/// ## Target-size algorithm (targetSizeMB > 0)
///   1. Measure source file size.
///   2. If source ≤ target → compress with the quality/bitrate preset (no extra work).
///   3. Compute video-only budget = targetBytes - audioBudget (128 kbps × durationSec).
///   4. Derive required bitrate = videoBudget / durationSec.
///   5. Clamp to [MIN_BITRATE … caller's explicit bitrate cap].
///   6. If the derived bitrate is < a per-resolution threshold, also scale the
///      resolution down proportionally so the codec can actually hit the target.
///      Resolution scale is clamped at MIN_SCALE (360p equivalent) to avoid
///      an unwatchable result.
@objc
class VideoProcessor: NSObject {

  typealias ProgressHandler = (_ progress: Float) -> Void
  typealias Completion = (_ result: [String: Any]?, _ error: Error?) -> Void

  // ─── Bitrate / quality constants ─────────────────────────────────────────
  private static let AUDIO_BITRATE_BPS: Double = 128_000
  /// Absolute minimum video bitrate — below this the picture quality is unacceptable
  private static let MIN_VIDEO_BITRATE: Double = 300_000   // 300 kbps
  /// Minimum output scale factor — never go below ~360p equivalent
  private static let MIN_SCALE: Double = 0.25
  /// H.265 practical quality floor (bits per pixel per frame).
  /// Below this threshold the picture becomes visually degraded at any standard bitrate.
  private static let MIN_BPP: Double = 0.07

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
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)"))
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

    guard let session = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetMediumQuality
    ) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session")); return
    }

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

    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      completion(nil, MediaToolkitError.processingFailed("No video track"))
      return
    }

    let naturalSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let fw = abs(naturalSize.width)
    let fh = abs(naturalSize.height)

    let cropX = CGFloat(x) * fw
    let cropY = CGFloat(y) * fh
    let cropW = CGFloat(width) * fw
    let cropH = CGFloat(height) * fh

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

    guard let session = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetMediumQuality
    ) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot create export session"))
      return
    }

    session.outputFileType   = .mp4
    session.outputURL        = outURL
    session.videoComposition = composition

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
  //
  // Engine: AVAssetReader + AVAssetWriter for full control.
  //
  // Why NOT AVAssetExportSession here:
  //   • Presets don't allow exact bitrate control (AVVideoAverageBitRateKey ignored)
  //   • No way to force HEVC codec on all iOS versions
  //
  // targetSizeMB algorithm:
  //   1. Get source file bytes.
  //   2. If source <= target, run normal quality-preset compress (no overwork).
  //   3. Subtract audio budget (128 kbps × duration) from total budget.
  //   4. Derive required video bitrate = videoBudget / duration.
  //   5. Clamp to [MIN_BITRATE … caller bitrate cap].
  //   6. If derived bitrate < threshold for current resolution, scale down resolution
  //      proportionally (keeping aspect ratio) so the encoder can actually hit it.

  @objc
  static func compressVideo(
    uri: String,
    quality: String,
    bitrate: Double,
    maxWidth: Double,
    muteAudio: Bool,
    targetSizeMB: Double,
    outputPath: String?,
    onProgress: @escaping ProgressHandler,
    completion: @escaping Completion
  ) {
    guard let asset = loadAsset(uri) else {
      completion(nil, MediaToolkitError.invalidInput("Cannot load video: \(uri)"))
      return
    }
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      completion(nil, MediaToolkitError.processingFailed("No video track found"))
      return
    }

    let out = outputPath ?? tempPath(ext: "mp4")
    let outURL = URL(fileURLWithPath: out)
    removeIfExists(outURL)

    let durationSec = asset.duration.seconds
    let naturalSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    var outW = abs(naturalSize.width)
    var outH = abs(naturalSize.height)

    // ─── Step 1: Resolve base bitrate from quality/explicit override ──────
    let baseBitrate: Double
    if bitrate > 0 {
      baseBitrate = bitrate
    } else {
      switch quality {
      case "low":  baseBitrate = 1_000_000
      case "high": baseBitrate = 6_000_000
      default:     baseBitrate = 2_500_000   // medium (H.265 looks great at 2.5 Mbps)
      }
    }

    // ─── Step 2: Apply maxWidth cap to dimensions ─────────────────────────
    if maxWidth > 0 && outW > CGFloat(maxWidth) {
      outH = outH * CGFloat(maxWidth) / outW
      outW = CGFloat(maxWidth)
    }

    // ─── Step 3: Target-size override ────────────────────────────────────
    var resolvedBitrate = baseBitrate
    if targetSizeMB > 0 {
      let sourcePath = uri.hasPrefix("file://") ? String(uri.dropFirst(7)) : uri
      let sourceBytes = (try? FileManager.default.attributesOfItem(atPath: sourcePath)[.size] as? Int64) ?? 0
      let targetBytes = targetSizeMB * 1_000_000

      if Double(sourceBytes) > targetBytes, durationSec > 0 {
        // Budget for audio (0 if muted)
        let audioBudget = muteAudio ? 0.0 : AUDIO_BITRATE_BPS * durationSec / 8.0
        let videoBudgetBytes = targetBytes - audioBudget
        let requiredBitrate = max(MIN_VIDEO_BITRATE, videoBudgetBytes * 8.0 / durationSec)

        // Never raise above the quality-preset cap
        resolvedBitrate = min(resolvedBitrate, requiredBitrate)

        // ── Resolution selection via standard ladder ──────────────────────
        // Why ladder instead of sqrt heuristic:
        //   • Hardware encoders (VideoToolbox, MediaCodec) have fast-paths for
        //     standard resolutions and may fall back to slower software paths
        //     for arbitrary non-standard sizes.
        //   • Predictable bit-per-pixel at known resolutions = better quality
        //     than a continuous scale that lands on e.g. 1147×645.
        //
        // Algorithm: walk DOWN the ladder and pick the highest width where
        //   bitrate / (width × height_at_aspect × fps) >= MIN_BPP.
        // Using 0.07 bpp/frame as the H.265 acceptable quality floor.
        let fps = Double(videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 30)
        let srcAspect = outH > 0 ? Double(outW / outH) : (16.0 / 9.0)
        // Standard widths, ordered high to low
        let ladder: [Double] = [3840, 2560, 1920, 1280, 960, 720, 640, 480, 360]
        let currentW = Double(outW)

        var selectedW = Double(outW)
        for rungW in ladder {
          // Only consider rungs ≤ current width (never upscale)
          guard rungW <= currentW else { continue }
          let rungH = (rungW / srcAspect).rounded()
          let pixels = rungW * rungH
          let bpp = resolvedBitrate / (pixels * fps)
          if bpp >= MIN_BPP {
            selectedW = rungW
            break       // highest rung that satisfies quality floor — take it
          }
        }

        // If even the lowest rung fails, keep lowest rung (360p) — better
        // than an unwatchable sub-360p result.
        if selectedW == currentW && Double(outW) > 360 {
          let rungH = (360.0 / srcAspect).rounded()
          let pixels = 360.0 * rungH
          if resolvedBitrate / (pixels * fps) < MIN_BPP {
            selectedW = max(360, ladder.last ?? 360)
          }
        }

        if selectedW < Double(outW) {
          outH = CGFloat(selectedW / srcAspect).rounded()
          outW = CGFloat(selectedW)
        }
      }
      // else: source already within budget — compress with base preset only
    }

    // ─── Step 4: Always ensure dimensions divisible by 2 (H.265 requirement)
    outW = CGFloat(Int(outW / 2) * 2)
    outH = CGFloat(Int(outH / 2) * 2)
    if outW < 2 { outW = 2 }
    if outH < 2 { outH = 2 }

    // ─── Step 5: Choose codec ─────────────────────────────────────────────
    // HEVC preferred — hardware encoder on A9+ chips, ~40-50% smaller files.
    let useHEVC = AVAssetExportSession.exportPresets(compatibleWith: asset)
      .contains(AVAssetExportPresetHEVCHighestQuality)
    let videoCodec = useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264

    // ─── Step 6: Build encoder settings ──────────────────────────────────
    let fps = videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 30
    var compressionProps: [String: Any] = [
      AVVideoAverageBitRateKey:        Int(resolvedBitrate),
      AVVideoAllowFrameReorderingKey:  true,
      AVVideoMaxKeyFrameIntervalKey:   Int(fps * 2),   // keyframe every 2 s
    ]
    if useHEVC {
      compressionProps[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
    } else {
      compressionProps[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
    }

    let videoOutputSettings: [String: Any] = [
      AVVideoCodecKey:                 videoCodec,
      AVVideoWidthKey:                 Int(outW),
      AVVideoHeightKey:                Int(outH),
      AVVideoCompressionPropertiesKey: compressionProps,
    ]

    // AAC audio at 128 kbps (transparent quality)
    let audioOutputSettings: [String: Any] = [
      AVFormatIDKey:         kAudioFormatMPEG4AAC,
      AVSampleRateKey:       44100,
      AVNumberOfChannelsKey: 2,
      AVEncoderBitRateKey:   Int(AUDIO_BITRATE_BPS),
    ]

    // ─── Step 7: Setup AVAssetReader ──────────────────────────────────────
    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      completion(nil, MediaToolkitError.processingFailed("Cannot create reader: \(error.localizedDescription)"))
      return
    }

    let videoReaderOutput = AVAssetReaderVideoCompositionOutput(
      videoTracks: asset.tracks(withMediaType: .video),
      videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
    )
    // Handle rotation + resize in one pass via video composition
    let videoComposition = AVMutableVideoComposition(propertiesOf: asset)
    videoComposition.renderSize = CGSize(width: outW, height: outH)
    videoReaderOutput.videoComposition = videoComposition
    videoReaderOutput.alwaysCopiesSampleData = false

    guard reader.canAdd(videoReaderOutput) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot add video reader output"))
      return
    }
    reader.add(videoReaderOutput)

    var audioReaderOutput: AVAssetReaderTrackOutput?
    if !muteAudio, let audioTrack = asset.tracks(withMediaType: .audio).first {
      let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
      output.alwaysCopiesSampleData = false
      if reader.canAdd(output) {
        reader.add(output)
        audioReaderOutput = output
      }
    }

    // ─── Step 8: Setup AVAssetWriter ──────────────────────────────────────
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
    } catch {
      completion(nil, MediaToolkitError.processingFailed("Cannot create writer: \(error.localizedDescription)"))
      return
    }

    let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
    videoWriterInput.expectsMediaDataInRealTime = false  // batch mode: as fast as possible
    guard writer.canAdd(videoWriterInput) else {
      completion(nil, MediaToolkitError.processingFailed("Cannot add video writer input"))
      return
    }
    writer.add(videoWriterInput)

    var audioWriterInput: AVAssetWriterInput?
    if audioReaderOutput != nil {
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
      input.expectsMediaDataInRealTime = false
      if writer.canAdd(input) {
        writer.add(input)
        audioWriterInput = input
      }
    }

    // ─── Step 9: Run encode ───────────────────────────────────────────────
    guard reader.startReading() else {
      completion(nil, reader.error ?? MediaToolkitError.processingFailed("Reader failed to start"))
      return
    }
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let totalDuration = durationSec
    let encodeQueue  = DispatchQueue(label: "com.mediatoolkit.compress", qos: .userInitiated)
    let group        = DispatchGroup()

    // Video encode loop
    group.enter()
    videoWriterInput.requestMediaDataWhenReady(on: encodeQueue) {
      while videoWriterInput.isReadyForMoreMediaData {
        if let sample = videoReaderOutput.copyNextSampleBuffer() {
          videoWriterInput.append(sample)
          let pts = CMSampleBufferGetDecodeTimeStamp(sample)
          if pts.isValid && totalDuration > 0 {
            onProgress(Float(min(pts.seconds / totalDuration, 0.95)))
          }
        } else {
          videoWriterInput.markAsFinished()
          group.leave()
          break
        }
      }
    }

    // Audio encode loop
    if let audioOut = audioReaderOutput, let audioIn = audioWriterInput {
      group.enter()
      audioIn.requestMediaDataWhenReady(on: encodeQueue) {
        while audioIn.isReadyForMoreMediaData {
          if let sample = audioOut.copyNextSampleBuffer() {
            audioIn.append(sample)
          } else {
            audioIn.markAsFinished()
            group.leave()
            break
          }
        }
      }
    }

    // Finish when both tracks done
    group.notify(queue: encodeQueue) {
      writer.finishWriting {
        if writer.status == .completed {
          onProgress(1.0)
          completion(videoResult(path: out, asset: asset, trimmed: durationSec * 1000), nil)
        } else {
          completion(nil, writer.error ?? MediaToolkitError.processingFailed("Write failed"))
        }
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
    return AVAsset(url: url)
  }

  private static func pollProgress(session: AVAssetExportSession, onProgress: @escaping ProgressHandler) {
    let startTime = Date()
    let estimatedDuration: TimeInterval = 8.0

    let timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { t in
      switch session.status {
      case .completed:
        onProgress(1.0); t.invalidate()
      case .failed, .cancelled:
        t.invalidate()
      case .exporting, .waiting:
        let elapsed = Date().timeIntervalSince(startTime)
        let timeFraction = min(elapsed / estimatedDuration, 1.0)
        let smoothEstimate = Float(1.0 - pow(1.0 - timeFraction, 2.5)) * 0.92
        let blended = smoothEstimate * 0.8 + session.progress * 0.2
        onProgress(min(blended, 0.95))
      default: break
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
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
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
