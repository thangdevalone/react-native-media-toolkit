package com.mediatoolkit

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

/**
 * React Native Package for MediaToolkit.
 * Nitro Modules are registered via JNI/OnLoad — this package is a no-op
 * but is required by the React Native autolinking system.
 */
@DoNotStrip
@Keep
class MediaToolkitPackage : ReactPackage {
  init {
    com.margelo.nitro.com.mediatoolkit.MediaToolkitOnLoad.initializeNative()
  }
  override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> = emptyList()
  override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> = emptyList()
}
