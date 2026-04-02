const { withMainApplication } = require('@expo/config-plugins');

/**
 * Expo Config Plugin — loads MediaToolkit C++ shared library at app startup.
 * Required by Nitro Modules to register the HybridObject on Android.
 * JNI_OnLoad in MediaToolkitOnLoad.cpp will auto-register all natives.
 */
const withMediaToolkitAndroid = (config) => {
  return withMainApplication(config, (mod) => {
    let contents = mod.modResults.contents;

    const initCall = 'System.loadLibrary("MediaToolkit")';
    if (!contents.includes(initCall)) {
      contents = contents.replace(
        /super\.onCreate\(\)\n/,
        `super.onCreate()\n    try { ${initCall} } catch (e: UnsatisfiedLinkError) { android.util.Log.e("MediaToolkit", "Failed to load MediaToolkit native lib", e) }\n`
      );
    }

    mod.modResults.contents = contents;
    return mod;
  });
};

module.exports = withMediaToolkitAndroid;
