# ------------------------------------------------------------------------------
# react-native-media-toolkit R8 / ProGuard Consumer Rules
#
# These rules are automatically packaged into the AAR and merged into the host
# application's ProGuard/R8 configuration when building in Release mode.
# ------------------------------------------------------------------------------

# 1. Keep the Nitro HybridObject implementation instantiated from C++ via JNI (fbjni)
# C++ calls JNI FindClass("com/margelo/nitro/com/mediatoolkit/HybridMediaToolkit")
# and invokes the default constructor:
-keep class com.margelo.nitro.com.mediatoolkit.HybridMediaToolkit {
    <init>();
    public *;
}

# 2. Keep all Nitrogen-generated spec classes, structs, data classes, and enums
-keep class com.margelo.nitro.com.mediatoolkit.** {
    <init>(...);
    *;
}

# 3. Keep React Native Package for autolinking reflection
-keep class com.mediatoolkit.MediaToolkitPackage {
    <init>();
    *;
}

# 4. Preserve classes & members annotated with @DoNotStrip or @Keep
-keep @com.facebook.proguard.annotations.DoNotStrip class * {
    @com.facebook.proguard.annotations.DoNotStrip *;
}
-keepclassmembers class * {
    @com.facebook.proguard.annotations.DoNotStrip *;
}

-keep @androidx.annotation.Keep class * {
    @androidx.annotation.Keep *;
}
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
