package com.mediatoolkit

import com.facebook.react.bridge.ReactApplicationContext

class MediaToolkitModule(reactContext: ReactApplicationContext) :
  NativeMediaToolkitSpec(reactContext) {

  override fun multiply(a: Double, b: Double): Double {
    return a * b
  }

  companion object {
    const val NAME = NativeMediaToolkitSpec.NAME
  }
}
