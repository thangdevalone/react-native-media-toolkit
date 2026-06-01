package com.margelo.nitro.com.mediatoolkit

import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import androidx.media3.common.util.UnstableApi

@UnstableApi
internal object MediaFilters {

    fun getColorMatrix(filterName: String?): FloatArray? {
        if (filterName == null) return null
        
        return when (filterName) {
            "bw" -> floatArrayOf(
                0.33f, 0.59f, 0.11f, 0f, 0f,
                0.33f, 0.59f, 0.11f, 0f, 0f,
                0.33f, 0.59f, 0.11f, 0f, 0f,
                0f, 0f, 0f, 1f, 0f
            )
            "vintage" -> floatArrayOf(
                0.393f, 0.769f, 0.189f, 0f, 0f,
                0.349f, 0.686f, 0.168f, 0f, 0f,
                0.272f, 0.534f, 0.131f, 0f, 0f,
                0f, 0f, 0f, 1f, 0f
            )
            "bright_pink" -> {
                // Brightness/contrast boost with slight pink tint
                // Boost R and B
                val contrast = 1.1f
                val brightness = 15f // offsets
                
                floatArrayOf(
                    1.15f * contrast, 0f, 0f, 0f, brightness, // R slightly boosted
                    0f, 1.0f * contrast, 0f, 0f, brightness,  // G normal
                    0f, 0f, 1.1f * contrast, 0f, brightness,  // B slightly boosted
                    0f, 0f, 0f, 1f, 0f
                )
            }
            else -> null
        }
    }
    
    fun getColorFilter(filterName: String?): ColorMatrixColorFilter? {
        val matrixArray = getColorMatrix(filterName) ?: return null
        return ColorMatrixColorFilter(ColorMatrix(matrixArray))
    }
    
    fun getMedia3Effect(filterName: String?): androidx.media3.common.Effect? {
        val matrixArray = getColorMatrix(filterName) ?: return null
        
        // RgbMatrix in Media3 expects a 4x4 matrix, but ColorMatrix is 4x5.
        // We extract the 4x4 scale part, omitting translation.
        return androidx.media3.effect.RgbMatrix { presentationTimeUs, useHdr ->
            floatArrayOf(
                matrixArray[0], matrixArray[1], matrixArray[2], matrixArray[3],
                matrixArray[5], matrixArray[6], matrixArray[7], matrixArray[8],
                matrixArray[10], matrixArray[11], matrixArray[12], matrixArray[13],
                matrixArray[15], matrixArray[16], matrixArray[17], matrixArray[18]
            )
        }
    }

    fun getLutEffect(context: android.content.Context, lutUri: String?): androidx.media3.common.Effect? {
        if (lutUri.isNullOrEmpty()) return null
        return try {
            val bmp = UriHelper.loadBitmap(context, lutUri)
            if (bmp == null) return null
            androidx.media3.effect.SingleColorLut.createFromBitmap(bmp)
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun applyLUTToBitmap(context: android.content.Context, src: android.graphics.Bitmap, lutUri: String?): android.graphics.Bitmap {
        if (lutUri.isNullOrEmpty()) return src
        val lutBmp = UriHelper.loadBitmap(context, lutUri)
        if (lutBmp == null) return src
        
        val width = src.width
        val height = src.height
        val pixels = IntArray(width * height)
        src.getPixels(pixels, 0, width, 0, 0, width, height)

        val lutWidth = lutBmp.width
        val lutPixels = IntArray(lutWidth * lutWidth)
        lutBmp.getPixels(lutPixels, 0, lutWidth, 0, 0, lutWidth, lutWidth)
        val dim = Math.cbrt(lutWidth.toDouble() * lutWidth.toDouble()).toInt()
        val rowNum = lutWidth / dim

        for (i in pixels.indices) {
            val color = pixels[i]
            val r = android.graphics.Color.red(color)
            val g = android.graphics.Color.green(color)
            val b = android.graphics.Color.blue(color)
            val a = android.graphics.Color.alpha(color)

            val lutX = (b * (dim - 1) / 255) % rowNum
            val lutY = (b * (dim - 1) / 255) / rowNum
            val x = lutX * dim + (r * (dim - 1) / 255)
            val y = lutY * dim + (g * (dim - 1) / 255)

            val lutIndex = y * lutWidth + x
            if (lutIndex < lutPixels.size) {
                val mapped = lutPixels[lutIndex]
                pixels[i] = android.graphics.Color.argb(a, android.graphics.Color.red(mapped), android.graphics.Color.green(mapped), android.graphics.Color.blue(mapped))
            }
        }

        val outBmp = android.graphics.Bitmap.createBitmap(width, height, src.config ?: android.graphics.Bitmap.Config.ARGB_8888)
        outBmp.setPixels(pixels, 0, width, 0, 0, width, height)
        lutBmp.recycle()
        return outBmp
    }
}
