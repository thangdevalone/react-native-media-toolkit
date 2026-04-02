package com.mediatoolkit

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

/**
 * React Native Package for MediaToolkit.
 * Nitro Modules are registered via JNI/OnLoad — this package is a no-op
 * but is required by the React Native autolinking system.
 */
class MediaToolkitPackage : ReactPackage {
  override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> = emptyList()
  override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> = emptyList()
}
