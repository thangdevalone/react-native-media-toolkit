const {
  withMainApplication,
  withGradleProperties,
  withAppBuildGradle,
} = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

/**
 * Expo Config Plugin for react-native-media-toolkit Android example.
 *
 * Applied automatically by Expo prebuild via app.json "plugins" entry.
 * Handles 3 things required for the monorepo composite build to work:
 *
 * 1. MainApplication: load MediaToolkit C++ shared library at startup.
 * 2. gradle.properties: disable Kotlin DSL accessor cache to prevent
 *    Gradle 8.13+ metadata.bin corruption bug in composite builds.
 * 3. gradle-wrapper.properties: pin Gradle to 8.13 (minimum required by
 *    AGP 8.7.2, maximum without metadata.bin regression from 8.14.x).
 */
const withMediaToolkitAndroid = (config) => {
  // ─── Step 1: Load native .so in MainApplication ───────────────────────────
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

  // ─── Step 2: Disable Kotlin DSL accessor cache ────────────────────────────
  // Gradle 8.13+ bug: kotlin-dsl metadata.bin gets corrupted when a build
  // fails mid-generation in composite/monorepo setups (includeBuild).
  // Setting cache=false forces regeneration every time — slightly slower
  // first build, no corruption.
  config = withGradleProperties(config, (mod) => {
    const props = mod.modResults;
    const key = 'org.gradle.kotlin.dsl.cache';
    if (!props.some((p) => p.type === 'property' && p.key === key)) {
      props.push({ type: 'property', key, value: 'false' });
    }
    mod.modResults = props;
    return mod;
  });

  // ─── Step 3: Pin Gradle wrapper to 8.13 ───────────────────────────────────
  // expo prebuild resets the Gradle wrapper to 8.14.x which has a breaking
  // Kotlin DSL workspace metadata regression. AGP 8.7.2 requires >= 8.13.
  // We pin to 8.13 which is stable with this project's RN 0.81 + Expo 54 setup.
  config = withAppBuildGradle(config, (mod) => {
    // withAppBuildGradle runs after prebuild writes files — hook to also patch wrapper
    const wrapperPath = path.join(
      mod.modRequest.projectRoot,
      'android/gradle/wrapper/gradle-wrapper.properties'
    );

    try {
      if (fs.existsSync(wrapperPath)) {
        let wrapper = fs.readFileSync(wrapperPath, 'utf8');
        // Replace any gradle-8.x.x-bin with gradle-8.13-bin
        const patched = wrapper.replace(
          /gradle-8\.\d+(\.\d+)?-bin/,
          'gradle-8.13-bin'
        );
        if (patched !== wrapper) {
          fs.writeFileSync(wrapperPath, patched, 'utf8');
          console.log('[withMediaToolkitAndroid] Pinned Gradle wrapper to 8.13');
        }
      }
    } catch (e) {
      console.warn('[withMediaToolkitAndroid] Could not patch gradle-wrapper.properties:', e.message);
    }

    return mod;
  });

  return config;
};

module.exports = withMediaToolkitAndroid;
