package com.mediatoolkit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/**
 * Image crop and compress using Android Bitmap API.
 * Handles EXIF orientation automatically.
 */
internal object ImageProcessor {

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
    val pw = (width * iw).toInt().coerceIn(1, iw - px)
    val ph = (height * ih).toInt().coerceIn(1, ih - py)

    val cropped = Bitmap.createBitmap(bmp, px, py, pw, ph)
    bmp.recycle()

    val out = outputPath ?: tempPath("jpg")
    FileOutputStream(out).use { fos ->
      cropped.compress(Bitmap.CompressFormat.JPEG, 90, fos)
    }

    return buildResult(out, cropped, "image/jpeg", 0)
  }

  // ─── COMPRESS ────────────────────────────────────────────────────────────

  fun compressImage(
    uri: String,
    quality: Int,
    maxWidth: Int,
    maxHeight: Int,
    format: String,
    outputPath: String?
  ): Map<String, Any> {
    val path = uriToPath(uri)
    var bmp = BitmapFactory.decodeFile(path)
      ?: throw MediaToolkitException("Cannot decode image: $uri")

    bmp = fixExifOrientation(bmp, path)
    bmp = resizeIfNeeded(bmp, maxWidth, maxHeight)

    val (compressFormat, ext, mime) = when (format) {
      "png"  -> Triple(Bitmap.CompressFormat.PNG,  "png", "image/png")
      "webp" -> Triple(
        if (android.os.Build.VERSION.SDK_INT >= 30)
          Bitmap.CompressFormat.WEBP_LOSSLESS
        else Bitmap.CompressFormat.WEBP,
        "webp", "image/webp"
      )
      else   -> Triple(Bitmap.CompressFormat.JPEG, "jpg", "image/jpeg")
    }

    val out = outputPath ?: tempPath(ext)
    val q = quality.coerceIn(0, 100)
    FileOutputStream(out).use { fos ->
      bmp.compress(compressFormat, q, fos)
    }

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

  private fun fixExifOrientation(bmp: Bitmap, path: String): Bitmap {
    return try {
      val exif = ExifInterface(path)
      val orientation = exif.getAttributeInt(
        ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
      )
      val matrix = Matrix()
      when (orientation) {
        ExifInterface.ORIENTATION_ROTATE_90  -> matrix.postRotate(90f)
        ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
        ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
        ExifInterface.ORIENTATION_FLIP_VERTICAL   -> matrix.postScale(1f, -1f)
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
    val mw = if (maxWidth > 0) maxWidth else bmp.width
    val mh = if (maxHeight > 0) maxHeight else bmp.height
    if (bmp.width <= mw && bmp.height <= mh) return bmp

    val ratio = minOf(mw.toFloat() / bmp.width, mh.toFloat() / bmp.height)
    val newW = (bmp.width * ratio).toInt()
    val newH = (bmp.height * ratio).toInt()
    val scaled = Bitmap.createScaledBitmap(bmp, newW, newH, true)
    bmp.recycle()
    return scaled
  }

  fun buildResult(path: String, bmp: Bitmap, mime: String, duration: Int): Map<String, Any> {
    val size = File(path).length()
    return mapOf(
      "uri"      to "file://$path",
      "size"     to size,
      "width"    to bmp.width,
      "height"   to bmp.height,
      "duration" to duration,
      "mime"     to mime
    )
  }
}
