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

    // Crop by scaling to fit the desired region then presenting at target aspect ratio.
    // x, y, width, height are in [0,1] relative to original frame.
    val aspectRatio = width / height.coerceAtLeast(0.001f)
    val presentation = Presentation.createForAspectRatio(
      aspectRatio,
      Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
    )
    val effects = Effects(emptyList(), listOf(presentation))

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

    val aspectRatio = width / height.coerceAtLeast(0.001f)
    val presentation = Presentation.createForAspectRatio(
      aspectRatio,
      Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
    )
    val effects = Effects(emptyList(), listOf(presentation))

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
    try {
        val retriever = android.media.MediaMetadataRetriever()
        val pathStr = if (mediaUri.scheme == "file") mediaUri.path else uri
        retriever.setDataSource(pathStr)
        durationMs = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        videoW = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
        videoH = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
        retriever.release()
    } catch (e: Exception) {}

    var computedBitrate = 0
    var finalWidth = videoW
    var finalHeight = videoH

    if (targetSizeInMB > 0 && durationMs > 0) {
        val durationSecs = durationMs / 1000.0
        var targetBits = (targetSizeInMB * 1024 * 1024 * 8) / durationSecs
        if (!muteAudio) { targetBits -= 96_000 } // audio reserve

        computedBitrate = targetBits.toInt()

        // Adaptive resolution heuristic
        val optimalRes = when {
            computedBitrate > 3_000_000 -> 1080.0
            computedBitrate > 1_500_000 -> 720.0
            computedBitrate > 800_000 -> 540.0
            else -> 480.0
        }
        
        val finalResTarget = maxOf(optimalRes, if (minResolution > 0) minResolution else 480.0)
        val shortEdge = minOf(videoW, videoH).toDouble()
        
        if (shortEdge > finalResTarget) {
            val scale = finalResTarget / shortEdge
            finalWidth = (videoW * scale).toInt()
            finalHeight = (videoH * scale).toInt()
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
    mainHandler.post {
      transformer.start(editedItem, outputPath)
    }

    // Poll progress on current thread
    val progressHolder = ProgressHolder()
    val progressThread = Thread {
      while (latch.count > 0) {
        transformer.getProgress(progressHolder)
        onProgress(progressHolder.progress)
        Thread.sleep(150)
      }
      onProgress(100)
    }
    progressThread.start()

    latch.await()
    progressThread.interrupt()

    exportError?.let { throw MediaToolkitException("Transform failed: ${it.message}") }

    return buildResult(outputPath, 0)
  }


  // ─── THUMBNAIL ──────────────────────────────────────────────────────────────

  fun getThumbnail(
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
      // Note: MediaMetadataRetriever needs a string path for file URIs
      val filePath = if (uri.startsWith("file://")) uri.removePrefix("file://") else uri
      retriever.setDataSource(filePath)

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
