package com.margelo.nitro.com.mediatoolkit

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.InputStream
import java.net.URL

internal object UriHelper {

    fun openInputStream(context: Context, uriString: String): InputStream? {
        if (uriString.isBlank()) return null
        val path = if (uriString.startsWith("file://")) uriString.removePrefix("file://") else uriString
        
        return try {
            if (path.startsWith("http://") || path.startsWith("https://")) {
                URL(path).openStream()
            } else {
                val uri = Uri.parse(uriString)
                when (uri.scheme) {
                    "content", "android.resource" -> {
                        context.contentResolver.openInputStream(uri)
                    }
                    "asset" -> {
                        val assetPath = uri.path?.removePrefix("/") ?: return null
                        context.assets.open(assetPath)
                    }
                    else -> {
                        // file:/// or raw path
                        java.io.FileInputStream(path)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun loadBitmap(context: Context, uriString: String, options: BitmapFactory.Options? = null): Bitmap? {
        return openInputStream(context, uriString)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, options)
        }
    }
}
