package com.margelo.nitro.com.mediatoolkit

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

  // ─── PROCESS (Crop + Flip + Rotate) ──────────────────────────────────────

  fun processImage(
    uri: String,
    cropX: Double,
    cropY: Double,
    cropWidth: Double,
    cropHeight: Double,
    flip: String?,
    rotation: Double,
    outputPath: String?
  ): Map<String, Any> {
    val path = uriToPath(uri)
    var bmp = BitmapFactory.decodeFile(path)
      ?: throw MediaToolkitException.InvalidInput("Cannot decode image: $uri")

    bmp = fixExifOrientation(bmp, path)

    // 1. Crop
    if (cropWidth > 0 && cropHeight > 0) {
      val iw = bmp.width
      val ih = bmp.height
      val px = (cropX * iw).toInt().coerceIn(0, iw - 1)
      val py = (cropY * ih).toInt().coerceIn(0, ih - 1)
      val pw = (cropWidth * iw).toInt().coerceIn(1, iw - px)
      val ph = (cropHeight * ih).toInt().coerceIn(1, ih - py)
      val cropped = Bitmap.createBitmap(bmp, px, py, pw, ph)
      if (cropped !== bmp) {
          bmp.recycle()
          bmp = cropped
      }
    }

    // 2. Transform (Flip / Rotate)
    if (!flip.isNullOrEmpty() || rotation != 0.0) {
      val matrix = Matrix()
      if (flip == "horizontal") {
          matrix.postScale(-1f, 1f, bmp.width / 2f, bmp.height / 2f)
      } else if (flip == "vertical") {
          matrix.postScale(1f, -1f, bmp.width / 2f, bmp.height / 2f)
      }
      if (rotation != 0.0) {
          matrix.postRotate(rotation.toFloat())
      }
      val transformed = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
      if (transformed !== bmp) {
          bmp.recycle()
          bmp = transformed
      }
    }

    val out = outputPath ?: tempPath("jpg")
    val written = FileOutputStream(out).use { fos ->
      bmp.compress(Bitmap.CompressFormat.JPEG, 90, fos)
    }
    if (!written) {
        bmp.recycle()
        throw MediaToolkitException.ProcessingFailed("Could not encode processed image")
    }

    return buildResult(out, bmp, "image/jpeg", 0)
  }

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
      ?: throw MediaToolkitException.InvalidInput("Cannot decode image: $uri")

    bmp = fixExifOrientation(bmp, path)

    val iw = bmp.width
    val ih = bmp.height

    val px = (x * iw).toInt().coerceIn(0, iw - 1)
    val py = (y * ih).toInt().coerceIn(0, ih - 1)
    val pw = (width * iw).toInt().coerceIn(1, iw - px)
    val ph = (height * ih).toInt().coerceIn(1, ih - py)

    val cropped = Bitmap.createBitmap(bmp, px, py, pw, ph)
      ?: run { bmp.recycle(); throw MediaToolkitException.ProcessingFailed("Bitmap crop failed") }
    bmp.recycle()

    val out = outputPath ?: tempPath("jpg")
    val written = FileOutputStream(out).use { fos ->
      cropped.compress(Bitmap.CompressFormat.JPEG, 90, fos)
    }
    if (!written) throw MediaToolkitException.ProcessingFailed("Could not encode cropped image")

    return buildResult(out, cropped, "image/jpeg", 0)
  }

  // ─── ROTATE ──────────────────────────────────────────────────────────────

  fun rotateImage(
    uri: String,
    degrees: Double,
    outputPath: String?
  ): Map<String, Any> {
    val path = uriToPath(uri)
    var bmp = BitmapFactory.decodeFile(path)
      ?: throw MediaToolkitException.InvalidInput("Cannot decode image: $uri")

    bmp = fixExifOrientation(bmp, path)

    val matrix = Matrix()
    matrix.postRotate(degrees.toFloat())
    val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
    if (rotated !== bmp) bmp.recycle()

    val out = outputPath ?: tempPath("jpg")
    val written = FileOutputStream(out).use { fos ->
      rotated.compress(Bitmap.CompressFormat.JPEG, 90, fos)
    }
    if (!written) throw MediaToolkitException.ProcessingFailed("Could not encode rotated image")

    return buildResult(out, rotated, "image/jpeg", 0)
  }

  // ─── FLIP ────────────────────────────────────────────────────────────────

  fun flipImage(
    uri: String,
    direction: String,
    outputPath: String?
  ): Map<String, Any> {
    val path = uriToPath(uri)
    var bmp = BitmapFactory.decodeFile(path)
      ?: throw MediaToolkitException.InvalidInput("Cannot decode image: $uri")

    bmp = fixExifOrientation(bmp, path)

    val matrix = Matrix()
    if (direction == "horizontal") {
      matrix.postScale(-1f, 1f, bmp.width / 2f, bmp.height / 2f)
    } else {
      matrix.postScale(1f, -1f, bmp.width / 2f, bmp.height / 2f)
    }
    val flipped = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
    if (flipped !== bmp) bmp.recycle()

    val out = outputPath ?: tempPath("jpg")
    val written = FileOutputStream(out).use { fos ->
      flipped.compress(Bitmap.CompressFormat.JPEG, 90, fos)
    }
    if (!written) throw MediaToolkitException.ProcessingFailed("Could not encode flipped image")

    return buildResult(out, flipped, "image/jpeg", 0)
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
    val options = BitmapFactory.Options()
    options.inJustDecodeBounds = true
    BitmapFactory.decodeFile(path, options)

    var rawW = options.outWidth
    var rawH = options.outHeight

    // Check EXIF to accurately base inSampleSize on visual dimensions
    val exif = try { ExifInterface(path) } catch (e: Exception) { null }
    val orientation = exif?.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) ?: ExifInterface.ORIENTATION_NORMAL
    if (orientation == ExifInterface.ORIENTATION_ROTATE_90 || orientation == ExifInterface.ORIENTATION_ROTATE_270) {
        rawW = options.outHeight
        rawH = options.outWidth
    }

    // High performance memory downsampling: Load 1/4 or 1/8 of the image directly from storage
    options.inJustDecodeBounds = false
    var sampleSize = 1
    if (maxWidth > 0 && maxHeight > 0) {
        while (rawW / (sampleSize * 2) >= maxWidth || rawH / (sampleSize * 2) >= maxHeight) {
            sampleSize *= 2
        }
    }
    options.inSampleSize = sampleSize

    var bmp = BitmapFactory.decodeFile(path, options)
      ?: throw MediaToolkitException.InvalidInput("Cannot decode image: $uri")

    bmp = fixExifOrientationDirect(bmp, orientation)
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
    val written = FileOutputStream(out).use { fos ->
      bmp.compress(compressFormat, q, fos)
    }
    if (!written) throw MediaToolkitException.ProcessingFailed("Could not encode image")

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
      fixExifOrientationDirect(bmp, orientation)
    } catch (_: Exception) {
      bmp
    }
  }

  private fun fixExifOrientationDirect(bmp: Bitmap, orientation: Int): Bitmap {
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
      return rotated
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
