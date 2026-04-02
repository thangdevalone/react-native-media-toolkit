module.exports = {
  dependency: {
    platforms: {
      // iOS is handled by CocoaPods automatically via the podspec
      ios: {},
      // Android: autolinking includes this as a Gradle module.
      // The CMakeLists.txt in android/ builds libMediaToolkit.so automatically.
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.mediatoolkit.MediaToolkitPackage;',
        packageInstance: 'new MediaToolkitPackage()',
      },
    },
  },
};
