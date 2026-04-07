package com.margelo.nitro.com.mediatoolkit

import android.content.Context
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import androidx.media3.effect.Presentation
import androidx.media3.common.util.UnstableApi
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Video trim, crop, compress using Jetpack Media3 Transformer.
 *
 * ## Compress strategy
 *   - H.265 (HEVC) preferred → ~40-50% smaller file at same perceived quality.
 *   - Exact bitrate via [VideoEncoderSettings.Builder.setBitrate].
 *   - Hardware MediaCodec encoder selected automatically (Snapdragon 845+, Exynos 9810+).
 *   - Falls back gracefully when HEVC encoder is unavailable.
 *
 * ## targetSizeMB algorithm
 *   1. Measure source file size.
 *   2. If source ≤ target → compress with quality-preset only (no extra work).
 *   3. Subtract audio budget (128 kbps × duration) from total budget.
 *   4. Derive required video bitrate = videoBudget / durationSec.
 *   5. Clamp to [MIN_BITRATE … caller bitrate cap].
 *   6. If the derived bitrate is below BITS_PER_PIXEL_MIN threshold for the current
 *      resolution, scale the resolution down proportionally (clamped at MIN_SCALE).
 *
 * All operations block the calling thread (call from bg thread/coroutine).
 */
@UnstableApi
internal object VideoProcessor {

  private const val AUDIO_BITRATE_BPS = 128_000.0        // 128 kbps AAC
  private const val MIN_VIDEO_BITRATE = 300_000.0        // absolute floor (300 kbps)
  private const val MIN_SCALE         = 0.25             // never go below ~360p equivalent
  private const val BITS_PER_PIXEL_MIN = 0.07            // H.265 practical floor (bpp/frame)

  // ─── TRIM ────────────────────────────────────────────────────────────────

  fun trimVideo(
    context: Context,
    uri: String,
    startMs: Long,
    endMs: Long,
    outputPath: String?,
    onProgress: (Int) -> Unit
  ): Map<String, Any> {
    val out = outputPath ?: tempPath()
    val mediaUri = toAndroidUri(uri)

    val clippingConfig = MediaItem.ClippingConfiguration.Builder()
      .setStartPositionMs(startMs)
      .setEndPositionMs(endMs)
      .build()

    val mediaItem = MediaItem.Builder()
      .setUri(mediaUri)
      .setClippingConfiguration(clippingConfig)
      .build()

    return runTransform(context, mediaItem, effects = Effects.EMPTY, out, onProgress, transmux = true)
  }

  // ─── CROP ────────────────────────────────────────────────────────────────

  fun cropVideo(
    context: Context,
    uri: String,
    x: Float,
    y: Float,
    width: Float,
    height: Float,
    outputPath: String?,
    onProgress: (Int) -> Unit
  ): Map<String, Any> {
    val out = outputPath ?: tempPath()
    val mediaItem = MediaItem.Builder().setUri(toAndroidUri(uri)).build()

    val aspectRatio = width / height.coerceAtLeast(0.001f)
    val presentation = Presentation.createForAspectRatio(
      aspectRatio, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
    )
    return runTransform(context, mediaItem, Effects(emptyList(), listOf(presentation)), out, onProgress)
  }

  // ─── TRIM + CROP (single pass) ───────────────────────────────────────────

  fun trimAndCropVideo(
    context: Context,
    uri: String,
    startMs: Long,
    endMs: Long,
    x: Float,
    y: Float,
    width: Float,
    height: Float,
    outputPath: String?,
    onProgress: (Int) -> Unit
  ): Map<String, Any> {
    val out = outputPath ?: tempPath()

    val clippingConfig = MediaItem.ClippingConfiguration.Builder()
      .setStartPositionMs(startMs)
      .setEndPositionMs(endMs)
      .build()

    val mediaItem = MediaItem.Builder()
      .setUri(toAndroidUri(uri))
      .setClippingConfiguration(clippingConfig)
      .build()

    val aspectRatio = width / height.coerceAtLeast(0.001f)
    val presentation = Presentation.createForAspectRatio(
      aspectRatio, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
    )
    // One encode pass: trim + crop combined
    return runTransform(
      context, mediaItem, Effects(emptyList(), listOf(presentation)), out, onProgress, transmux = false
    )
  }

  // ─── COMPRESS ────────────────────────────────────────────────────────────

  fun compressVideo(
    context: Context,
    uri: String,
    quality: String,
    bitrate: Int,          // 0 = use quality preset
    maxWidth: Int,
    muteAudio: Boolean,
    targetSizeMB: Double,  // 0 = disabled
    outputPath: String?,
    onProgress: (Int) -> Unit
  ): Map<String, Any> {
    val out = outputPath ?: tempPath()
    val mediaUri = toAndroidUri(uri)

    // ─── Step 1: Base bitrate from quality/explicit override ──────────────
    // medium = 2.5 Mbps (H.265 produces the same perceived quality as 4 Mbps H.264)
    val baseBitrate = when {
      bitrate > 0       -> bitrate.toDouble()
      quality == "low"  -> 1_000_000.0
      quality == "high" -> 6_000_000.0
      else              -> 2_500_000.0   // medium
    }

    // ─── Step 2: Measure source dimensions & duration ─────────────────────
    val retriever = android.media.MediaMetadataRetriever()
    var srcWidth  = 0
    var srcHeight = 0
    var durationSec = 0.0
    try {
      val filePath = if (uri.startsWith("file://")) uri.removePrefix("file://") else uri
      retriever.setDataSource(filePath)
      srcWidth    = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()  ?: 0
      srcHeight   = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
      durationSec = (retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) / 1000.0
    } finally {
      retriever.release()
    }

    // ─── Step 3: Apply maxWidth cap ───────────────────────────────────────
    var outWidth  = if (maxWidth > 0 && srcWidth > maxWidth) maxWidth else srcWidth
    var outHeight = if (maxWidth > 0 && srcWidth > 0 && srcWidth > maxWidth)
      (srcHeight * maxWidth.toDouble() / srcWidth).toInt() else srcHeight

    // ─── Step 4: targetSizeMB override ───────────────────────────────────
    var resolvedBitrate = baseBitrate
    if (targetSizeMB > 0 && durationSec > 0) {
      val filePath = if (uri.startsWith("file://")) uri.removePrefix("file://") else uri
      val sourceBytes = File(filePath).length().toDouble()
      val targetBytes = targetSizeMB * 1_000_000  // SI: 1 MB = 1,000,000 bytes

      if (sourceBytes > targetBytes) {
        // Budget minus audio (0 if muted)
        val audioBudget = if (muteAudio) 0.0 else AUDIO_BITRATE_BPS * durationSec / 8.0
        val videoBudgetBytes = targetBytes - audioBudget
        val requiredBitrate = max(MIN_VIDEO_BITRATE, videoBudgetBytes * 8.0 / durationSec)

        // Never raise above the quality-preset cap
        resolvedBitrate = min(resolvedBitrate, requiredBitrate)

        // ── Resolution selection via standard ladder ───────────────────────────
        // Why ladder instead of sqrt heuristic:
        //   • MediaCodec has hardware fast-paths for standard resolutions
        //     (1920, 1280, 720...) and may use slower software paths for
        //     arbitrary non-standard sizes like 1147×645.
        //   • Standard resolutions have well-known quality characteristics,
        //     making BPP thresholds more predictable.
        //
        // Walk DOWN the ladder and pick the highest width where
        //   bitrate / (width × height_at_aspect × fps) >= BITS_PER_PIXEL_MIN.
        val fps = 30.0  // conservative estimate; Media3 uses actual source fps internally
        val srcAspect = if (outHeight > 0) outWidth.toDouble() / outHeight.toDouble() else 16.0 / 9.0
        val ladder = intArrayOf(3840, 2560, 1920, 1280, 960, 720, 640, 480, 360)
        val currentW = outWidth

        var selectedW = currentW
        for (rungW in ladder) {
          if (rungW > currentW) continue   // never upscale
          val rungH = (rungW / srcAspect).toInt()
          val pixels = rungW.toDouble() * rungH.toDouble()
          val bpp = resolvedBitrate / (pixels * fps)
          if (bpp >= BITS_PER_PIXEL_MIN) {
            selectedW = rungW
            break  // highest rung satisfying quality floor — take it
          }
        }

        // If even 360p fails the BPP floor, clamp to 360 (always better than sub-360)
        if (selectedW == currentW && currentW > 360) {
          val rungH = (360.0 / srcAspect).toInt()
          val pixels = 360.0 * rungH
          if (resolvedBitrate / (pixels * fps) < BITS_PER_PIXEL_MIN) {
            selectedW = 360
          }
        }

        if (selectedW < currentW) {
          outHeight = max(2, (selectedW / srcAspect).toInt() / 2 * 2)
          outWidth  = selectedW
        }
      }
      // else: source already within budget — compress with preset only
    }

    // ─── Step 5: Build Media3 effects (resize presentation) ──────────────
    val effects: Effects = if (outWidth > 0 && outWidth != srcWidth) {
      val presentation = Presentation.createForWidthAndHeight(
        outWidth, outHeight, Presentation.LAYOUT_SCALE_TO_FIT
      )
      Effects(emptyList(), listOf(presentation))
    } else if (maxWidth > 0) {
      val presentation = Presentation.createForWidthAndHeight(
        maxWidth, maxWidth, Presentation.LAYOUT_SCALE_TO_FIT
      )
      Effects(emptyList(), listOf(presentation))
    } else {
      Effects.EMPTY
    }

    val mediaItem = MediaItem.Builder().setUri(mediaUri).build()

    return runTransform(
      context, mediaItem, effects, out, onProgress,
      targetBitrate = resolvedBitrate.toInt(),
      removeAudio   = muteAudio,
      preferHEVC    = true
    )
  }

  // ─── Core ────────────────────────────────────────────────────────────────

  private fun runTransform(
    context: Context,
    mediaItem: MediaItem,
    effects: Effects,
    outputPath: String,
    onProgress: (Int) -> Unit,
    transmux: Boolean = false,
    targetBitrate: Int = 0,        // 0 = let Media3 decide
    removeAudio: Boolean = false,
    preferHEVC: Boolean = false
  ): Map<String, Any> {
    val outFile = File(outputPath)
    outFile.parentFile?.mkdirs()
    if (outFile.exists()) outFile.delete()

    val latch = CountDownLatch(1)
    var exportError: Exception? = null

    val editedItemBuilder = EditedMediaItem.Builder(mediaItem).setEffects(effects)
    if (removeAudio) editedItemBuilder.setRemoveAudio(true)
    val editedItem = editedItemBuilder.build()

    val transformerBuilder = Transformer.Builder(context)
      .addListener(object : Transformer.Listener {
        override fun onCompleted(composition: Composition, result: ExportResult) {
          latch.countDown()
        }
        override fun onError(composition: Composition, result: ExportResult, exception: ExportException) {
          exportError = exception
          latch.countDown()
        }
      })

    if (transmux) {
      // Passthrough: remux without re-encoding — fast trim, zero quality loss
      transformerBuilder.setVideoMimeType(MimeTypes.VIDEO_H264)
    } else {
      // H.265 preferred: hardware MediaCodec selected automatically
      // Media3 falls back to H.264 if HEVC encode fails on the device
      transformerBuilder.setVideoMimeType(if (preferHEVC) MimeTypes.VIDEO_H265 else MimeTypes.VIDEO_H264)

      // Apply exact bitrate (FIXED: was computed but ignored in old version)
      if (targetBitrate > 0) {
        val encoderSettings = VideoEncoderSettings.Builder()
          .setBitrate(targetBitrate)
          .build()
        transformerBuilder.setVideoEncoderSettings(encoderSettings)
      }
    }

    val transformer = transformerBuilder.build()

    // Media3 Transformer must be started on the main thread
    val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    mainHandler.post { transformer.start(editedItem, outputPath) }

    // Poll progress on calling thread
    val progressHolder = ProgressHolder()
    val progressThread = Thread {
      try {
        while (latch.count > 0) {
          transformer.getProgress(progressHolder)
          onProgress(progressHolder.progress)
          Thread.sleep(150)
        }
        onProgress(100)
      } catch (_: InterruptedException) { /* normal exit */ }
    }
    progressThread.isDaemon = true
    progressThread.start()

    latch.await()
    progressThread.interrupt()

    exportError?.let { throw MediaToolkitException("Transform failed: ${it.message}") }

    return buildResult(outputPath, 0)
  }

  // ─── THUMBNAIL ────────────────────────────────────────────────────────────

  fun getThumbnail(
    uri: String,
    timeMs: Long,
    quality: Int,
    maxWidth: Int,
    outputPath: String?
  ): Map<String, Any> {
    val retriever = android.media.MediaMetadataRetriever()
    try {
      val filePath = if (uri.startsWith("file://")) uri.removePrefix("file://") else uri
      retriever.setDataSource(filePath)

      val bitmap = retriever.getFrameAtTime(
        timeMs * 1000L,
        android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
      ) ?: throw MediaToolkitException("Could not extract frame at ${timeMs}ms")

      val scaledBitmap = if (maxWidth > 0 && bitmap.width > maxWidth) {
        val scale = maxWidth.toFloat() / bitmap.width
        val newH = (bitmap.height * scale).toInt()
        android.graphics.Bitmap.createScaledBitmap(bitmap, maxWidth, newH, true)
          .also { if (it !== bitmap) bitmap.recycle() }
      } else bitmap

      val q = quality.coerceIn(0, 100)
      val out = outputPath ?: (System.getProperty("java.io.tmpdir") + "/${UUID.randomUUID()}.jpg")
      java.io.FileOutputStream(out).use { fos ->
        scaledBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, q, fos)
      }
      if (scaledBitmap !== bitmap) scaledBitmap.recycle()
      bitmap.recycle()

      val file = File(out)
      return mapOf(
        "uri"    to "file://$out",
        "size"   to file.length(),
        "width"  to scaledBitmap.width,
        "height" to scaledBitmap.height
      )
    } finally {
      retriever.release()
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  private fun toAndroidUri(uri: String): Uri =
    if (uri.startsWith("file://") || uri.startsWith("content://")) Uri.parse(uri)
    else Uri.fromFile(File(uri))

  fun tempPath(): String {
    val dir = System.getProperty("java.io.tmpdir") ?: "/data/local/tmp"
    File(dir).mkdirs()
    return "$dir/${UUID.randomUUID()}.mp4"
  }

  private fun buildResult(path: String, durationMs: Long): Map<String, Any> {
    val file = File(path)
    val retriever = android.media.MediaMetadataRetriever()
    var width = 0; var height = 0; var duration = durationMs
    try {
      retriever.setDataSource(path)
      width    = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()  ?: 0
      height   = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
      if (duration == 0L)
        duration = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
    } finally {
      retriever.release()
    }
    return mapOf(
      "uri"      to "file://$path",
      "size"     to file.length(),
      "width"    to width,
      "height"   to height,
      "duration" to duration,
      "mime"     to "video/mp4"
    )
  }
}
