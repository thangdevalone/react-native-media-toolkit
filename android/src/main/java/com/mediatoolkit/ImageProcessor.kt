package com.margelo.nitro.com.mediatoolkit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Image crop and compress using Android Bitmap API.
 * Handles EXIF orientation automatically.
 *
 * ## targetSizeMB algorithm (binary-search quality)
 *   1. Resize to maxWidth/maxHeight (if provided).
 *   2. If targetSizeMB is set and the image is still too large:
 *      - Binary-search JPEG quality between 1 and the caller's quality cap.
 *      - If even quality=1 exceeds the target, halve the resolution and retry.
 *      - Repeats up to 3 resolution halvings (clamped to MIN_SCALE).
 *   PNG/WebP: lossless, so only resolution reduction is applied for targetSizeMB.
 */
internal object ImageProcessor {

  private const val MIN_SCALE = 0.1   // never go below 10% of original dimensions

  // ─── CROP ────────────────────────────────────────────────────────────────

  fun cropImage(
    uri: String,
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    outputPath: String?
  ): Map<String, Any> {
    val path = uriToPath(uri)
    var bmp = BitmapFactory.decodeFile(path)
      ?: throw MediaToolkitException("Cannot decode image: $uri")

    bmp = fixExifOrientation(bmp, path)

    val iw = bmp.width
    val ih = bmp.height
    val px = (x * iw).toInt().coerceIn(0, iw - 1)
    val py = (y * ih).toInt().coerceIn(0, ih - 1)
    val pw = (width  * iw).toInt().coerceIn(1, iw - px)
    val ph = (height * ih).toInt().coerceIn(1, ih - py)

    val cropped = Bitmap.createBitmap(bmp, px, py, pw, ph)
    bmp.recycle()

    val out = outputPath ?: tempPath("jpg")
    FileOutputStream(out).use { fos -> cropped.compress(Bitmap.CompressFormat.JPEG, 90, fos) }

    return buildResult(out, cropped, "image/jpeg", 0)
  }

  // ─── COMPRESS ────────────────────────────────────────────────────────────

  fun compressImage(
    uri: String,
    quality: Int,
    maxWidth: Int,
    maxHeight: Int,
    format: String,
    targetSizeMB: Double,  // 0 = disabled
    outputPath: String?
  ): Map<String, Any> {
    val path = uriToPath(uri)
    var bmp = BitmapFactory.decodeFile(path)
      ?: throw MediaToolkitException("Cannot decode image: $uri")

    bmp = fixExifOrientation(bmp, path)
    bmp = resizeIfNeeded(bmp, maxWidth, maxHeight)

    val (compressFormat, ext, mime) = when (format) {
      "png"  -> Triple(Bitmap.CompressFormat.PNG, "png", "image/png")
      "webp" -> Triple(
        if (android.os.Build.VERSION.SDK_INT >= 30) Bitmap.CompressFormat.WEBP_LOSSY
        else @Suppress("DEPRECATION") Bitmap.CompressFormat.WEBP,
        "webp", "image/webp"
      )
      else   -> Triple(Bitmap.CompressFormat.JPEG, "jpg", "image/jpeg")
    }

    val out = outputPath ?: tempPath(ext)
    val maxQ = quality.coerceIn(1, 100)
    val targetBytes = if (targetSizeMB > 0) (targetSizeMB * 1_000_000).toLong() else Long.MAX_VALUE

    // ── PNG / WebP lossless: no quality dial — resize only ────────────────
    if (format == "png") {
      bmp = resizeForTargetBytes(bmp, targetBytes, Bitmap.CompressFormat.PNG, 100)
      FileOutputStream(out).use { fos -> bmp.compress(Bitmap.CompressFormat.PNG, 100, fos) }
      return buildResult(out, bmp, mime, 0)
    }

    // ── JPEG / WebP lossy: estimation-guided binary search ─────────────
    val data = if (targetSizeMB > 0) {
      // Encode at maxQ once. Reuse byte count for size estimation.
      val initialBaos = compressToBaos(bmp, compressFormat, maxQ)
      if (initialBaos.size() <= targetBytes) {
        // Already within budget — done in 1 encode, no search needed
        initialBaos.toByteArray()
      } else {
        // Estimate target quality using JPEG size/quality power law:
        //   size ≈ K × q^0.75  ⇒  q_est = maxQ × (target/current)^(1/0.75)
        // This is usually within ±15% of the true answer.
        val sizeRatio = targetBytes.toDouble() / initialBaos.size().toDouble()
        val estimatedQ = (maxQ * Math.pow(sizeRatio, 1.333)).toInt().coerceIn(1, maxQ - 1)

        // Narrow search: ±40% around estimate, then fall back to full range if needed
        val loNarrow = max(1, (estimatedQ * 0.6).toInt())
        val hiNarrow = min(maxQ, (estimatedQ * 1.4).toInt())
        estimationGuidedSearch(bmp, compressFormat, maxQ, targetBytes, loNarrow, hiNarrow)
          ?: run {
            // If estimate was far off (very dense image), try left side of range
            estimationGuidedSearch(bmp, compressFormat, maxQ, targetBytes, 1, loNarrow)
              ?: run {
                // Resolution fallback: scale down and retry
                val scaled = resizeForTargetBytes(bmp, targetBytes, compressFormat, maxQ)
                estimationGuidedSearch(scaled, compressFormat, maxQ, targetBytes, 1, maxQ)
                  ?: compressToBaos(scaled, compressFormat, 1).toByteArray()
              }
          }
      }
    } else {
      compressToBaos(bmp, compressFormat, maxQ).toByteArray()
    }

    FileOutputStream(out).use { fos -> fos.write(data) }
    return buildResult(out, bmp, mime, 0)
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  fun uriToPath(uri: String): String =
    if (uri.startsWith("file://")) uri.removePrefix("file://") else uri

  fun tempPath(ext: String): String {
    val dir = System.getProperty("java.io.tmpdir") ?: "/data/local/tmp"
    File(dir).mkdirs()
    return "$dir/${UUID.randomUUID()}.$ext"
  }

  /**
   * Estimation-guided binary search for JPEG/WebP quality.
   * Searches only in the range [loRange, hiRange] — caller should narrow this
   * using an empirical estimate before calling.
   * Returns the best ByteArray found within [targetBytes], or null if none found.
   */
  private fun estimationGuidedSearch(
    bmp: Bitmap,
    format: Bitmap.CompressFormat,
    maxQ: Int,
    targetBytes: Long,
    loRange: Int,
    hiRange: Int
  ): ByteArray? {
    var lo = loRange.coerceIn(1, maxQ)
    var hi = hiRange.coerceIn(lo, maxQ)
    var best: ByteArray? = null

    repeat(5) {   // 5 iterations on narrowed range ≈ 8 iterations on full [1,100]
      val mid = (lo + hi) / 2
      val baos = compressToBaos(bmp, format, mid)
      if (baos.size() <= targetBytes) {
        lo = mid + 1
        best = baos.toByteArray()
      } else {
        hi = mid - 1
      }
    }
    return best
  }

  /** Full-range binary search, kept for fallback. */
  private fun binarySearchQuality(
    bmp: Bitmap,
    format: Bitmap.CompressFormat,
    maxQ: Int,
    targetBytes: Long
  ): ByteArray? = estimationGuidedSearch(bmp, format, maxQ, targetBytes, 1, maxQ)

  /**
   * Halve the resolution of [bmp] up to 3 times (clamped to MIN_SCALE) until a
   * single encode at [maxQ] fits in [targetBytes]. Used as fallback when the
   * binary-search quality loop alone is insufficient.
   */
  private fun resizeForTargetBytes(
    bmp: Bitmap,
    targetBytes: Long,
    format: Bitmap.CompressFormat,
    maxQ: Int
  ): Bitmap {
    var current = bmp
    var scale = 1.0
    repeat(3) {
      val baos = compressToBaos(current, format, maxQ)
      if (baos.size() <= targetBytes) return current
      scale = max(scale * 0.5, MIN_SCALE)
      val newW = max(2, (bmp.width  * scale).toInt())
      val newH = max(2, (bmp.height * scale).toInt())
      val scaled = Bitmap.createScaledBitmap(bmp, newW, newH, true)
      if (current !== bmp) current.recycle()
      current = scaled
      if (scale <= MIN_SCALE) return current
    }
    return current
  }

  private fun compressToBaos(
    bmp: Bitmap,
    format: Bitmap.CompressFormat,
    quality: Int
  ): ByteArrayOutputStream {
    val baos = ByteArrayOutputStream()
    bmp.compress(format, quality, baos)
    return baos
  }

  private fun fixExifOrientation(bmp: Bitmap, path: String): Bitmap {
    return try {
      val exif = ExifInterface(path)
      val orientation = exif.getAttributeInt(
        ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
      )
      val matrix = Matrix()
      when (orientation) {
        ExifInterface.ORIENTATION_ROTATE_90        -> matrix.postRotate(90f)
        ExifInterface.ORIENTATION_ROTATE_180       -> matrix.postRotate(180f)
        ExifInterface.ORIENTATION_ROTATE_270       -> matrix.postRotate(270f)
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL  -> matrix.postScale(-1f, 1f)
        ExifInterface.ORIENTATION_FLIP_VERTICAL    -> matrix.postScale(1f, -1f)
        else -> return bmp
      }
      val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
      bmp.recycle()
      rotated
    } catch (_: Exception) {
      bmp
    }
  }

  private fun resizeIfNeeded(bmp: Bitmap, maxWidth: Int, maxHeight: Int): Bitmap {
    val mw = if (maxWidth  > 0) maxWidth  else bmp.width
    val mh = if (maxHeight > 0) maxHeight else bmp.height
    if (bmp.width <= mw && bmp.height <= mh) return bmp

    val ratio = minOf(mw.toFloat() / bmp.width, mh.toFloat() / bmp.height)
    val newW = (bmp.width  * ratio).toInt()
    val newH = (bmp.height * ratio).toInt()
    val scaled = Bitmap.createScaledBitmap(bmp, newW, newH, true)
    bmp.recycle()
    return scaled
  }

  fun buildResult(path: String, bmp: Bitmap, mime: String, duration: Int): Map<String, Any> {
    return mapOf(
      "uri"      to "file://$path",
      "size"     to File(path).length(),
      "width"    to bmp.width,
      "height"   to bmp.height,
      "duration" to duration,
      "mime"     to mime
    )
  }
}
