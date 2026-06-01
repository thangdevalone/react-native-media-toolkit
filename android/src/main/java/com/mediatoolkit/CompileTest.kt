package com.margelo.nitro.com.mediatoolkit

import androidx.media3.effect.Contrast
import androidx.media3.effect.RgbMatrix

class CompileTest {
    fun t() {
        val c = Contrast(1.1f)
        val r = RgbMatrix { _, _ -> FloatArray(16) }
    }
}
