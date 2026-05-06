package com.margelo.nitro.com.mediatoolkit

import android.content.Context
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.SpeedChangeEffect
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch

/**
 * Video trim, crop, compress using Jetpack Media3 Transformer.
 * All operations block the calling thread (call from bg thread/coroutine).
 */
@UnstableApi
internal object VideoProcessor {
  private const val MAX_GIF_TOTAL_PIXELS = 40_000_000L

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

    val clippingConfig = androidx.media3.common.MediaItem.ClippingConfiguration.Builder()
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
    val mediaUri = toAndroidUri(uri)
    val mediaItem = MediaItem.Builder().setUri(mediaUri).build()

    // x, y, width, height are in [0,1] relative to original frame.
    // Media3 Crop uses Normalized Device Coordinates (NDC) [-1, 1], where (-1, -1) is bottom-left.
    val left = x * 2.0f - 1.0f
    val right = (x + width) * 2.0f - 1.0f
    val top = 1.0f - y * 2.0f
    val bottom = 1.0f - (y + height) * 2.0f

    val cropEffect = androidx.media3.effect.Crop(left, right, bottom, top)
    val effects = Effects(emptyList(), listOf(cropEffect))

    return runTransform(context, mediaItem, effects, out, onProgress)
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

    val clippingConfig = androidx.media3.common.MediaItem.ClippingConfiguration.Builder()
      .setStartPositionMs(startMs)
      .setEndPositionMs(endMs)
      .build()

    val mediaItem = MediaItem.Builder()
      .setUri(toAndroidUri(uri))
      .setClippingConfiguration(clippingConfig)
      .build()

    // Media3 Crop uses Normalized Device Coordinates (NDC) [-1, 1], where (-1, -1) is bottom-left.
    val left = x * 2.0f - 1.0f
    val right = (x + width) * 2.0f - 1.0f
    val top = 1.0f - y * 2.0f
    val bottom = 1.0f - (y + height) * 2.0f

    val cropEffect = androidx.media3.effect.Crop(left, right, bottom, top)
    val effects = Effects(emptyList(), listOf(cropEffect))

    // Must re-encode for crop, but only ONE pass (faster than trim then crop)
    return runTransform(context, mediaItem, effects, out, onProgress, transmux = false)
  }

  // ─── PROCESS (Trim + Crop + Flip + Rotate) ───────────────────────────────

  fun processVideo(
    context: Context,
    uri: String,
    startMs: Long,
    endMs: Long,
    cropX: Float,
    cropY: Float,
    cropWidth: Float,
    cropHeight: Float,
    flip: String?,
    rotation: Double,
    outputPath: String?,
    onProgress: (Int) -> Unit
  ): Map<String, Any> {
    val out = outputPath ?: tempPath()

    val clippingConfig = if (startMs > 0 || endMs > 0) {
      androidx.media3.common.MediaItem.ClippingConfiguration.Builder()
        .setStartPositionMs(startMs)
        .setEndPositionMs(if (endMs > 0) endMs else Long.MIN_VALUE) // Using default end behavior
        .build()
    } else {
      androidx.media3.common.MediaItem.ClippingConfiguration.UNSET
    }

    val mediaItem = MediaItem.Builder()
      .setUri(toAndroidUri(uri))
      .setClippingConfiguration(clippingConfig)
      .build()

    val effectList = mutableListOf<androidx.media3.common.Effect>()

    // 1. Crop
    if (cropWidth > 0 && cropHeight > 0) {
      val left = cropX * 2.0f - 1.0f
      val right = (cropX + cropWidth) * 2.0f - 1.0f
      val top = 1.0f - cropY * 2.0f
      val bottom = 1.0f - (cropY + cropHeight) * 2.0f
      effectList.add(androidx.media3.effect.Crop(left, right, bottom, top))
    }

    // 2. Transform (Flip/Rotate)
    if (!flip.isNullOrEmpty() || rotation != 0.0) {
      val scaleX = if (flip == "horizontal") -1f else 1f
      val scaleY = if (flip == "vertical") -1f else 1f
      effectList.add(
        ScaleAndRotateTransformation.Builder()
          .setScale(scaleX, scaleY)
          .setRotationDegrees(rotation.toFloat())
          .build()
      )
    }

    val effects = Effects(emptyList(), effectList)

    return runTransform(context, mediaItem, effects, out, onProgress, transmux = false)
  }

  // ─── ROTATE ──────────────────────────────────────────────────────────────

  fun rotateVideo(
    context: Context,
    uri: String,
    degrees: Double,
    outputPath: String?,
    onProgress: (Int) -> Unit
  ): Map<String, Any> {
    val out = outputPath ?: tempPath()
    val mediaUri = toAndroidUri(uri)
    val mediaItem = MediaItem.Builder().setUri(mediaUri).build()

    val rotateEffect = ScaleAndRotateTransformation.Builder().setRotationDegrees(degrees.toFloat()).build()
    val effects = Effects(emptyList(), listOf(rotateEffect))

    return runTransform(context, mediaItem, effects, out, onProgress)
  }

  // ─── FLIP ────────────────────────────────────────────────────────────────

  fun flipVideo(
    context: Context,
    uri: String,
    direction: String,
    outputPath: String?,
    onProgress: (Int) -> Unit
  ): Map<String, Any> {
    val out = outputPath ?: tempPath()
    val mediaUri = toAndroidUri(uri)
    val mediaItem = MediaItem.Builder().setUri(mediaUri).build()

    val scaleX = if (direction == "horizontal") -1f else 1f
    val scaleY = if (direction == "vertical") -1f else 1f
    val flipEffect = ScaleAndRotateTransformation.Builder().setScale(scaleX, scaleY).build()
    val effects = Effects(emptyList(), listOf(flipEffect))

    return runTransform(context, mediaItem, effects, out, onProgress)
  }

  // ─── CHANGE SPEED ────────────────────────────────────────────────────────
  fun changeVideoSpeed(
    context: Context,
    uri: String,
    speed: Double,
    outputPath: String?,
    onProgress: (Int) -> Unit
  ): Map<String, Any> {
    val out = outputPath ?: tempPath()
    val mediaUri = toAndroidUri(uri)
    val mediaItem = MediaItem.Builder().setUri(mediaUri).build()

    val sonicAudioProcessor = SonicAudioProcessor()
    sonicAudioProcessor.setSpeed(speed.toFloat())
    sonicAudioProcessor.setPitch(1.0f)

    val speedEffect = SpeedChangeEffect(speed.toFloat())
    val effects = Effects(listOf(sonicAudioProcessor), listOf(speedEffect))

    return runTransform(context, mediaItem, effects, out, onProgress)
  }

  // ─── EXTRACT AUDIO ───────────────────────────────────────────────────────
  fun extractAudio(
    context: Context,
    uri: String,
    outputPath: String?,
    onProgress: (Int) -> Unit
  ): Map<String, Any> {
    val out = outputPath ?: tempPath("m4a")
    val mediaUri = toAndroidUri(uri)
    val mediaItem = MediaItem.Builder().setUri(mediaUri).build()

    return runTransform(context, mediaItem, Effects.EMPTY, out, onProgress, removeVideo = true)
  }

  // ─── GENERATE PREVIEW (GIF) ──────────────────────────────────────────────
  fun generateVideoPreview(
    context: Context,
    uri: String,
    fps: Int,
    durationMs: Int,
    maxWidth: Int,
    quality: Int,
    outputPath: String?
  ): Map<String, Any> {
    val retriever = android.media.MediaMetadataRetriever()
    try {
      retriever.setDataSource(context, toAndroidUri(uri))
      
      val actualDuration = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
      val captureDuration = minOf(actualDuration, durationMs.toLong())
      var sourceWidth = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
      var sourceHeight = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
      val sourceRotation = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
      if (sourceRotation == 90 || sourceRotation == 270) {
        val tmp = sourceWidth
        sourceWidth = sourceHeight
        sourceHeight = tmp
      }
      
      val framesToCapture = (captureDuration / 1000.0 * fps).toInt()
      if (framesToCapture <= 0) throw MediaToolkitException.ProcessingFailed("Video is too short for preview")

      val plannedSize = scaledSize(sourceWidth, sourceHeight, maxWidth)
      val totalPixels = plannedSize.first.toLong() * plannedSize.second.toLong() * framesToCapture.toLong()
      if (plannedSize.first > 0 && plannedSize.second > 0 && totalPixels > MAX_GIF_TOTAL_PIXELS) {
        throw MediaToolkitException.InvalidInput(
          "GIF is too large: ${plannedSize.first}x${plannedSize.second} x $framesToCapture frames. Use maxWidth 320/540/720 or a shorter duration."
        )
      }

      val out = outputPath ?: tempPath("gif")
      
      val encoder = AnimatedGifEncoder()
      encoder.start(out)
      encoder.setDelay(1000 / fps)
      encoder.setRepeat(0) // 0 = infinite loop
      
      // Quality mapping: 1 is best, 20 is fast/lower. Default is 10.
      val q = quality.coerceIn(0, 100)
      val mappedQuality = maxOf(1, 21 - (q / 5)) 
      encoder.setQuality(mappedQuality)

      var outWidth = 0
      var outHeight = 0
      
      for (i in 0 until framesToCapture) {
        val timeMs = (i.toDouble() / fps * 1000.0).toLong()
        val bitmap = retriever.getFrameAtTime(timeMs * 1000L, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        if (bitmap != null) {
          val scaledBitmap = if (maxWidth > 0 && bitmap.width > maxWidth) {
            val scale = maxWidth.toFloat() / bitmap.width
            val newH = (bitmap.height * scale).toInt()
            android.graphics.Bitmap.createScaledBitmap(bitmap, maxWidth, newH, true)
              .also { if (it !== bitmap) bitmap.recycle() }
          } else bitmap

          if (outWidth == 0) {
             outWidth = scaledBitmap.width
             outHeight = scaledBitmap.height
          }
          encoder.addFrame(scaledBitmap)
          scaledBitmap.recycle()
        }
      }
      encoder.finish()

      if (outWidth == 0 || outHeight == 0) {
        val bounds = android.graphics.BitmapFactory.Options().apply {
          inJustDecodeBounds = true
        }
        android.graphics.BitmapFactory.decodeFile(out, bounds)
        if (bounds.outWidth > 0 && bounds.outHeight > 0) {
          outWidth = bounds.outWidth
          outHeight = bounds.outHeight
        }
      }

      if (outWidth == 0 || outHeight == 0) {
        val scaled = scaledSize(sourceWidth, sourceHeight, maxWidth)
        outWidth = scaled.first
        outHeight = scaled.second
      }
      
      val outFile = File(out)
      return mapOf(
        "uri"      to "file://$out",
        "size"     to outFile.length(),
        "width"    to outWidth,
        "height"   to outHeight,
        "duration" to captureDuration,
        "mime"     to "image/gif"
      )
    } catch (e: Exception) {
      if (e is MediaToolkitException) throw e
      throw MediaToolkitException.ProcessingFailed("Failed to generate preview: ${e.message}")
    } finally {
      retriever.release()
    }
  }

  // ─── COMPRESS ────────────────────────────────────────────────────────────

  fun compressVideo(
    context: Context,
    uri: String,
    quality: String,
    bitrate: Int,          // 0 = use quality preset (matches iOS behaviour)
    targetSizeInMB: Double,
    minResolution: Double,
    maxWidth: Int,
    muteAudio: Boolean,
    outputPath: String?,
    onProgress: (Int) -> Unit
  ): Map<String, Any> {
    val out = outputPath ?: tempPath()
    val mediaUri = toAndroidUri(uri)
    val mediaItem = MediaItem.Builder().setUri(mediaUri).build()

    // Get duration and dimensions using MediaMetadataRetriever
    var durationMs = 0L
    var videoW = 0
    var videoH = 0
    var origBitrate = 0
    var origSizeMB = 0.0
    try {
        val retriever = android.media.MediaMetadataRetriever()
        val pathStr: String = if (mediaUri.scheme == "file") mediaUri.path ?: uri else uri
        
        val f = java.io.File(pathStr)
        if (f.exists()) origSizeMB = f.length() / (1024.0 * 1024.0)
        
        if (mediaUri.scheme == "content") {
            try {
                context.contentResolver.query(mediaUri, null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val sizeIndex = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                        if (sizeIndex != -1) {
                            val size = cursor.getLong(sizeIndex)
                            if (size > 0) origSizeMB = size / (1024.0 * 1024.0)
                        }
                    }
                }
                if (origSizeMB <= 0) {
                    context.contentResolver.openFileDescriptor(mediaUri, "r")?.use { pfd ->
                        origSizeMB = pfd.statSize / (1024.0 * 1024.0)
                    }
                }
            } catch (ignored: Exception) {}
            retriever.setDataSource(context, mediaUri)
        } else {
            retriever.setDataSource(pathStr)
        }
        
        durationMs = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        videoW = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
        videoH = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
        
        val rotation = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        
        android.util.Log.d("VideoProcessor", "Original Metadata: w=\${videoW}, h=\${videoH}, rot=\${rotation}")
        
        if (rotation == 90 || rotation == 270) {
            val tmp = videoW
            videoW = videoH
            videoH = tmp
        }
        
        origBitrate = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
        retriever.release()
    } catch (e: Exception) {
        android.util.Log.e("VideoProcessor", "Metadata extraction failed", e)
    }

    var computedBitrate = 0
    var finalWidth = videoW
    var finalHeight = videoH

    if (targetSizeInMB > 0 && durationMs > 0) {
        val durationSecs = durationMs / 1000.0
        val shortEdge = minOf(videoW, videoH).toDouble()

        // --- Impossible Compression Rejection Logic ---
        val minRequiredBitrate = 400_000 + if (muteAudio) 0 else 96_000
        val minRequiredMB = (durationSecs * minRequiredBitrate) / (8.0 * 1024 * 1024)
        if (targetSizeInMB < minRequiredMB) {
            val reqMBStr = String.format("%.1f", minRequiredMB)
            throw MediaToolkitException.InvalidInput("Target size (${targetSizeInMB}MB) is impossible for a ${durationSecs.toInt()}s video. Minimum required limit is ~${reqMBStr}MB to prevent corruption.")
        }
        if (origSizeMB > 0 && targetSizeInMB >= origSizeMB) {
            val reqMBStr = String.format("%.1f", origSizeMB)
            throw MediaToolkitException.InvalidInput("Target size (${targetSizeInMB}MB) must be smaller than the original video size (${reqMBStr}MB).")
        }
        if (origSizeMB > 0 && targetSizeInMB < (origSizeMB * 0.05)) {
            throw MediaToolkitException.InvalidInput("Target size is too extreme (< 5% of original). The encoder hardware will fail to squeeze it.")
        }
        // ----------------------------------------------

        // Calculate exact target pixels based on standard encoder bits-per-pixel-per-sec (BPPPS)
        // Android H.264 hardware encoders typically output ~4.0 to 5.0 bits/pixel/sec.
        val TARGET_BPPPS = 4.5
        var targetBitsPerSec = (targetSizeInMB * 1024 * 1024 * 8) / durationSecs
        if (!muteAudio) { targetBitsPerSec -= 128_000 }
        if (targetBitsPerSec < 100_000) targetBitsPerSec = 100_000.0

        val targetPixels = targetBitsPerSec / TARGET_BPPPS
        val currentPixels = videoW.toDouble() * videoH.toDouble()

        var scale = Math.sqrt(targetPixels / currentPixels)
        if (scale > 1.0) scale = 1.0 // Never upscale

        var computedShortEdge = shortEdge * scale

        if (minResolution > 0 && minResolution > shortEdge) {
            throw MediaToolkitException.InvalidInput("minResolution (${minResolution.toInt()}p) exceeds video's actual resolution (${shortEdge.toInt()}p). Cannot upscale beyond original.")
        }

        // Calculate a safe minimum resolution floor to prevent extreme pixelation.
        // We ensure resolution never drops below ~33% of original, with a hard floor of 240p.
        val autoMinRes = maxOf(240.0, shortEdge * 0.33)
        
        // Use user's minResolution if valid, otherwise use the safe auto floor.
        val effectiveMinRes = if (minResolution > 0) minResolution.toDouble() else minOf(autoMinRes, shortEdge)

        if (computedShortEdge < effectiveMinRes) {
            if (minResolution > 0) {
                // The user explicitly requested a minimum resolution that physically conflicts with the requested target size.
                // Instead of silently forcing the resolution (which inflates the file size) or silently shrinking it (which ruins quality),
                // we throw an error to let the developer know they asked for the impossible.
                throw MediaToolkitException.InvalidInput("Conflict: To reach target size ${targetSizeInMB}MB, resolution must drop to ~${computedShortEdge.toInt()}p, which violates your minResolution (${minResolution}p). Please increase targetSize or decrease minResolution.")
            } else {
                // No minResolution was explicitly provided, so we just use the safe auto floor to avoid extreme blurriness.
                android.util.Log.w("VideoProcessor", "Target size ${targetSizeInMB}MB requires ${computedShortEdge.toInt()}p, but capping at auto safe minimum ${effectiveMinRes.toInt()}p. File may overshoot target size.")
                computedShortEdge = effectiveMinRes
                scale = computedShortEdge / shortEdge
            }
        }

        finalWidth = (videoW * scale).toInt()
        finalHeight = (videoH * scale).toInt()
        if (finalWidth % 2 != 0) finalWidth -= 1
        if (finalHeight % 2 != 0) finalHeight -= 1

        android.util.Log.d("VideoProcessor", "Mathematical Prediction: scale=${String.format("%.3f", scale)}, res=${finalWidth}x${finalHeight}")

        // Use 65% margin for setBitrate since hardware encoders overshoot
        var targetBits = ((targetSizeInMB * 0.65) * 1024 * 1024 * 8) / durationSecs
        if (!muteAudio) { targetBits -= 128_000 }
        computedBitrate = targetBits.toInt()

        if (computedBitrate > 20_000_000) computedBitrate = 20_000_000
        if (computedBitrate < 200_000) computedBitrate = 200_000

        if (origBitrate > 0 && computedBitrate > (origBitrate * 0.70).toInt()) {
            computedBitrate = (origBitrate * 0.70).toInt()
        }
    } else {
        computedBitrate = when {
          bitrate > 0 -> bitrate
          quality == "low"  -> 1_000_000
          quality == "high" -> 8_000_000
          else              -> 4_000_000
        }
    }

    if (maxWidth > 0 && finalWidth > maxWidth) {
        val scale = maxWidth.toDouble() / finalWidth
        finalWidth = maxWidth
        finalHeight = (finalHeight * scale).toInt()
        if (finalWidth % 2 != 0) finalWidth -= 1
        if (finalHeight % 2 != 0) finalHeight -= 1
    }

    android.util.Log.d("VideoProcessor", "Smart Compress: target=${targetSizeInMB}MB, computedBitrate=${computedBitrate}, finalRes=${finalWidth}x${finalHeight}")

    val effects: Effects = if (finalWidth != videoW || finalHeight != videoH) {
      val presentation = Presentation.createForWidthAndHeight(finalWidth, finalHeight, Presentation.LAYOUT_SCALE_TO_FIT)
      Effects(emptyList(), listOf(presentation))
    } else {
      Effects.EMPTY
    }

    val result = runTransform(context, mediaItem, effects, out, onProgress, targetBitrate = computedBitrate, removeAudio = muteAudio)

    // Fallback: If hardware encoder inflates the file (e.g. because minResolution forced a high resolution),
    // and no audio stripping was requested, revert to the original file to prevent size inflation.
    if (origSizeMB > 0 && !muteAudio) {
        val outFile = File(out)
        if (outFile.exists()) {
            val finalSizeMB = outFile.length() / (1024.0 * 1024.0)
            if (finalSizeMB > origSizeMB) {
                android.util.Log.w("VideoProcessor", "Hardware encoder inflated file from ${origSizeMB}MB to ${finalSizeMB}MB. Reverting to original file.")
                if (mediaUri.scheme == "content") {
                    context.contentResolver.openInputStream(mediaUri)?.use { input ->
                        outFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                } else {
                    val srcPath: String = if (mediaUri.scheme == "file") mediaUri.path ?: uri else uri
                    java.io.File(srcPath).copyTo(outFile, overwrite = true)
                }
            }
        }
    }

    return result
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
    removeAudio: Boolean = false,  // true = strip audio track
    removeVideo: Boolean = false   // true = strip video track
  ): Map<String, Any> {
    val outFile = File(outputPath)
    outFile.parentFile?.mkdirs()
    if (outFile.exists()) outFile.delete()

    val latch = CountDownLatch(1)
    var exportError: Exception? = null

    val editedItemBuilder = EditedMediaItem.Builder(mediaItem)
      .setEffects(effects)
    if (removeAudio) {
      editedItemBuilder.setRemoveAudio(true)
    }
    if (removeVideo) {
      editedItemBuilder.setRemoveVideo(true)
    }
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
      // Passthrough: remux without re-encoding — fast trim
      transformerBuilder.setVideoMimeType(MimeTypes.VIDEO_H264)
    } else {
      if (targetBitrate > 0) {
        val videoSettings = androidx.media3.transformer.VideoEncoderSettings.Builder()
            .setBitrate(targetBitrate)
            .build()
        val encoderFactory = androidx.media3.transformer.DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(videoSettings)
            .build()
        transformerBuilder.setEncoderFactory(encoderFactory)
        // Use H.264: more mature encoders on Android, better bitrate compliance than HEVC.
        transformerBuilder.setVideoMimeType(MimeTypes.VIDEO_H264)
      } else {
        transformerBuilder.setVideoMimeType(MimeTypes.VIDEO_H264)
      }
    }

    val transformer = transformerBuilder.build()

    // Run on main thread (Media3 requirement), then wait
    val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    val progressHolder = ProgressHolder()

    val progressRunnable = object : Runnable {
      override fun run() {
        if (latch.count == 0L) {
          onProgress(100)
          return
        }
        try {
          transformer.getProgress(progressHolder)
          onProgress(progressHolder.progress)
        } catch (e: Exception) {}
        mainHandler.postDelayed(this, 150)
      }
    }

    mainHandler.post {
      try {
        transformer.start(editedItem, outputPath)
        mainHandler.postDelayed(progressRunnable, 150)
      } catch (e: Exception) {
        exportError = e
        latch.countDown()
      }
    }

    latch.await()

    exportError?.let { throw MediaToolkitException.ProcessingFailed("Transform failed: ${it.message}") }

    return buildResult(outputPath, 0)
  }


  // ─── THUMBNAIL ──────────────────────────────────────────────────────────────

  fun getThumbnail(
    context: Context,
    uri: String,
    timeMs: Long,
    quality: Int,
    maxWidth: Int,
    outputPath: String?
  ): Map<String, Any> {
    val retriever = android.media.MediaMetadataRetriever()
    try {
      val uriParsed = if (uri.startsWith("file://") || uri.startsWith("content://"))
        android.net.Uri.parse(uri) else android.net.Uri.fromFile(java.io.File(uri))

      try {
        if (uri.startsWith("content://")) {
           retriever.setDataSource(context, uriParsed)
        } else {
           val filePath = if (uri.startsWith("file://")) uri.removePrefix("file://") else uri
           retriever.setDataSource(filePath)
        }
      } catch (e: Exception) {
        throw MediaToolkitException.InvalidInput("Cannot load video: $uri")
      }

      // getFrameAtTime takes microseconds
      val bitmap = retriever.getFrameAtTime(
        timeMs * 1000L,
        android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
      ) ?: throw MediaToolkitException.ProcessingFailed("Could not extract frame at ${timeMs}ms")

      // Source video dimensions (rotation-corrected) — NOT the scaled thumbnail dims
      var srcW = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: bitmap.width
      var srcH = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: bitmap.height
      val rotation = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
      if (rotation == 90 || rotation == 270) { val tmp = srcW; srcW = srcH; srcH = tmp }

      // Downscale thumbnail image if requested
      val scaledBitmap = if (maxWidth > 0 && bitmap.width > maxWidth) {
        val scale = maxWidth.toFloat() / bitmap.width
        val newH = (bitmap.height * scale).toInt()
        android.graphics.Bitmap.createScaledBitmap(bitmap, maxWidth, newH, true)
          .also { if (it !== bitmap) bitmap.recycle() }
      } else bitmap

      val q = quality.coerceIn(0, 100)
      val out = outputPath ?: (System.getProperty("java.io.tmpdir") + "/" + java.util.UUID.randomUUID() + ".jpg")
      val written = java.io.FileOutputStream(out).use { fos ->
        scaledBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, q, fos)
      }
      if (!written) throw MediaToolkitException.ProcessingFailed("Failed to encode JPEG thumbnail")
      if (scaledBitmap !== bitmap) scaledBitmap.recycle()
      bitmap.recycle()

      // Source video file size (NOT thumbnail file size)
      val srcFilePath = if (uri.startsWith("file://")) uri.removePrefix("file://") else uri
      val srcFileSize = java.io.File(srcFilePath).length()

      // Source video duration in milliseconds
      val srcDurationMs = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L

      return mapOf(
        "uri"      to "file://$out",
        "size"     to srcFileSize,      // source video file size
        "width"    to srcW,             // source video width
        "height"   to srcH,             // source video height
        "duration" to srcDurationMs     // source video duration in ms
      )
    } finally {
      retriever.release()
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────


  private fun toAndroidUri(uri: String): Uri =
    if (uri.startsWith("file://") || uri.startsWith("content://")) Uri.parse(uri)
    else Uri.fromFile(File(uri))

  fun tempPath(ext: String = "mp4"): String {
    val dir = System.getProperty("java.io.tmpdir") ?: "/data/local/tmp"
    File(dir).mkdirs()
    return "$dir/${UUID.randomUUID()}.$ext"
  }

  private fun buildResult(path: String, durationMs: Long): Map<String, Any> {
    val file = File(path)
    val size = file.length()
    // Extract video dimensions via MediaMetadataRetriever
    val retriever = android.media.MediaMetadataRetriever()
    var width = 0; var height = 0; var duration = durationMs
    try {
      retriever.setDataSource(path)
      width = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
      height = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
      
      val rotation = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
      if (rotation == 90 || rotation == 270) {
          val tmp = width
          width = height
          height = tmp
      }
      
      // Always read ACTUAL duration from output file (not the passed parameter)
      duration = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: durationMs
    } finally {
      retriever.release()
    }
    return mapOf(
      "uri"      to "file://$path",
      "size"     to size,
      "width"    to width,
      "height"   to height,
      "duration" to duration,
      "mime"     to "video/mp4"
    )
  }

  private fun scaledSize(width: Int, height: Int, maxWidth: Int): Pair<Int, Int> {
    if (width <= 0 || height <= 0) return 0 to 0
    if (maxWidth <= 0 || width <= maxWidth) return width to height
    val scale = maxWidth.toDouble() / width.toDouble()
    return maxWidth to (height * scale).toInt()
  }
}
