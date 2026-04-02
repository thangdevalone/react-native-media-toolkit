const { withMainApplication, withGradleProperties, withAppBuildGradle } = require('@expo/config-plugins');

/**
 * Expo Config Plugin for react-native-media-toolkit on Android.
 *
 * Does three things:
 * 1. Loads the MediaToolkit C++ shared library at app startup (required by Nitro Modules).
 * 2. Disables Kotlin DSL workspace metadata caching to fix Gradle 8.13+ metadata.bin
 *    corruption bug in composite/monorepo builds.
 * 3. Adds `android.packaging.resources.pickFirsts` and `android.packaging.jniLibs.pickFirsts`
 *    to resolve duplicate DEX class errors when react-native-safe-area-context is used alongside
 *    this library in a monorepo composite build (includeBuild) setup.
 */
const withMediaToolkitAndroid = (config) => {
  // Step 1: Load native library in MainApplication
  config = withMainApplication(config, (mod) => {
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

  // Step 2: Disable Kotlin DSL workspace metadata cache.
  // Gradle 8.13+ has a bug where the kotlin-dsl accessor metadata.bin file becomes
  // unreadable when a build fails mid-generation in composite/monorepo setups.
  // Setting this to false forces Gradle to regenerate accessors on every build
  // (slightly slower first build, but eliminates the corruption bug).
  config = withGradleProperties(config, (mod) => {
    const props = mod.modResults;
    const key = 'org.gradle.kotlin.dsl.cache';
    if (!props.some((p) => p.type === 'property' && p.key === key)) {
      props.push({ type: 'property', key, value: 'false' });
    }
    mod.modResults = props;
    return mod;
  });

  // Step 3: Resolve duplicate DEX class errors in composite build monorepo.
  // Background: react-native-media-toolkit uses includeBuild in the example/android/settings.gradle.
  // The library has `compileOnly "com.facebook.react:react-android"`, but in composite build mode,
  // Gradle may include react-android's codegen classes (e.g. RNCSafeAreaProviderManagerDelegate)
  // in the library's bundleLibRuntimeToDir DEX. react-native-safe-area-context ALSO ships these
  // same classes. AGP 8.x `android.packaging.resources.pickFirsts` resolves class file conflicts.
  config = withAppBuildGradle(config, (mod) => {
    let contents = mod.modResults.contents;
    const marker = '// MediaToolkit: resolve safe-area DEX conflict';

    if (!contents.includes(marker)) {
      // Insert inside the android {} block, after the existing packagingOptions/androidResources
      const pickFirstsBlock = `
    ${marker}
    // When react-native-safe-area-context is installed alongside this library in a
    // monorepo (composite build / includeBuild), react-android's bundled codegen stubs
    // conflict with safe-area-context's own codegen stubs. pickFirsts tells AGP to
    // keep only one copy of these classes instead of failing the build.
    packaging {
        resources {
            pickFirsts += [
                '**/com/facebook/react/viewmanagers/RNCSafeAreaProviderManagerDelegate.class',
                '**/com/facebook/react/viewmanagers/RNCSafeAreaViewManagerDelegate.class',
                '**/com/facebook/react/viewmanagers/RNCSafeAreaProviderManager.class',
                '**/com/facebook/react/viewmanagers/RNCSafeAreaViewManager.class',
            ]
        }
    }`;

      // Insert before the closing of android { } block
      contents = contents.replace(
        /(\n    androidResources \{[^}]*\})\n(\})/,
        `$1${pickFirstsBlock}\n$2`
      );

      mod.modResults.contents = contents;
    }

    return mod;
  });

  return config;
};

module.exports = withMediaToolkitAndroid;
