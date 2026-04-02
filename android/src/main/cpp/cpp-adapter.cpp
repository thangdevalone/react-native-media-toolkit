///
/// cpp-adapter.cpp
/// This is the JNI entry point for the MediaToolkit native library.
/// When System.loadLibrary("MediaToolkit") is called from Java/Kotlin,
/// the JVM invokes JNI_OnLoad, which registers all HybridObjects in the
/// Nitro HybridObjectRegistry so they can be created from JS via NitroModulesProxy.
///

#include <jni.h>
#include <fbjni/fbjni.h>
#include "MediaToolkitOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return facebook::jni::initialize(vm, []() {
    // Register all Nitro HybridObjects for MediaToolkit.
    // This maps the string "MediaToolkit" → HybridMediaToolkit Kotlin class.
    margelo::nitro::mediatoolkit::registerAllNatives();
  });
}
