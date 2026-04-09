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

        // Determine final resolution
        var optimalRes = 480.0
        if (targetSizeInMB > 0) {
            val targetBits = (targetSizeInMB * 1024 * 1024 * 8) / durationSecs
            optimalRes = when {
                targetBits > 3_000_000 -> 1080.0
                targetBits > 1_500_000 -> 720.0
                targetBits > 800_000 -> 540.0
                else -> 480.0
            }
        }
        val finalResTarget = if (minResolution > 0) minResolution else optimalRes
        val shortEdge = minOf(videoW, videoH).toDouble()
        
        android.util.Log.d("VideoProcessor", "Resolution Check: optimal=\${optimalRes}, finalResTarget=\${finalResTarget}, shortEdge=\${shortEdge}")
        
        if (shortEdge > finalResTarget) {
            val scale = finalResTarget / shortEdge
            finalWidth = (videoW * scale).toInt()
            finalHeight = (videoH * scale).toInt()
            if (finalWidth % 2 != 0) finalWidth -= 1
            if (finalHeight % 2 != 0) finalHeight -= 1
        }
        
        android.util.Log.d("VideoProcessor", "Effect Dimensions: finalW=\${finalWidth}, finalH=\${finalHeight}")

        if (origSizeMB > 0 && targetSizeInMB >= origSizeMB) {
            // File is already under target size. 
            // Varry the compression purely based on the resolution reduction!
            val pixelRatio = (finalWidth.toDouble() * finalHeight) / maxOf(1, videoW * videoH)
            // Bitrate scales down roughly with sqrt of pixel reduction, capped at 90% of original
            val bitScale = minOf(0.90, Math.max(0.3, Math.sqrt(pixelRatio)))
            computedBitrate = (origBitrate * bitScale).toInt()
            if (computedBitrate < 400_000) computedBitrate = 400_000 // absolute floor
        } else {
            // File is OVER target size. Squeeze it strictly into target bounds.
            // Apply a 90% safety margin to account for VBR (Variable Bitrate) overshoot and MP4 container overhead
            var targetBits = ((targetSizeInMB * 0.90) * 1024 * 1024 * 8) / durationSecs
            if (!muteAudio) { targetBits -= 128_000 } // audio reserve (128kbps)
            computedBitrate = targetBits.toInt()
        }
        
        // Prevent extreme bitrates that cause java.lang.OutOfMemoryError (e.g. short video, high target)
        if (computedBitrate > 20_000_000) computedBitrate = 20_000_000
        
        if (origBitrate > 0 && computedBitrate > origBitrate) {
            computedBitrate = origBitrate
        }
    } else {
        computedBitrate = when {
          bitrate > 0 -> bitrate           // explicit override wins
          quality == "low"  -> 1_000_000
          quality == "high" -> 8_000_000
          else              -> 4_000_000   // medium
        }
    }

    if (maxWidth > 0 && finalWidth > maxWidth) {
        val scale = maxWidth.toDouble() / finalWidth
        finalWidth = maxWidth
        finalHeight = (finalHeight * scale).toInt()
        if (finalWidth % 2 != 0) finalWidth -= 1
        if (finalHeight % 2 != 0) finalHeight -= 1
    }

    val effects: Effects = if (finalWidth != videoW || finalHeight != videoH) {
      val presentation = Presentation.createForWidthAndHeight(
        finalWidth, finalHeight,
        Presentation.LAYOUT_SCALE_TO_FIT
      )
      Effects(emptyList(), listOf(presentation))
    } else {
      Effects.EMPTY
    }

    return runTransform(context, mediaItem, effects, out, onProgress, targetBitrate = computedBitrate, removeAudio = muteAudio)
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
    removeAudio: Boolean = false   // true = strip audio track (Locket upload)
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
        transformerBuilder.setVideoMimeType(MimeTypes.VIDEO_H265) // Use HEVC for high compression Smart Compress
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

    exportError?.let { throw MediaToolkitException("Transform failed: ${it.message}") }

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
        
      if (uri.startsWith("content://")) {
         retriever.setDataSource(context, uriParsed)
      } else {
         val filePath = if (uri.startsWith("file://")) uri.removePrefix("file://") else uri
         retriever.setDataSource(filePath)
      }

      // getFrameAtTime takes microseconds
      val bitmap = retriever.getFrameAtTime(
        timeMs * 1000L,
        android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
      ) ?: throw MediaToolkitException("Could not extract frame at ${timeMs}ms")

      // Downscale if requested
      val scaledBitmap = if (maxWidth > 0 && bitmap.width > maxWidth) {
        val scale = maxWidth.toFloat() / bitmap.width
        val newH = (bitmap.height * scale).toInt()
        android.graphics.Bitmap.createScaledBitmap(bitmap, maxWidth, newH, true)
          .also { if (it !== bitmap) bitmap.recycle() }
      } else bitmap

      val q = quality.coerceIn(0, 100)
      val out = outputPath ?: (System.getProperty("java.io.tmpdir") + "/" + java.util.UUID.randomUUID() + ".jpg")
      java.io.FileOutputStream(out).use { fos ->
        scaledBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, q, fos)
      }
      if (scaledBitmap !== bitmap) scaledBitmap.recycle()
      bitmap.recycle()

      val file = java.io.File(out)
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
      
      if (duration == 0L) {
        duration = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
      }
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
}
