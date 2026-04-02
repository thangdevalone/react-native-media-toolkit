module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.mediatoolkit.MediaToolkitPackage;',
        packageInstance: 'new MediaToolkitPackage()',
        buildTypes: ['debug', 'release'],
        libraryName: 'MediaToolkit',
        componentDescriptors: [],
        cmakeListsPath: './android/CMakeLists.txt',
      },
      ios: {},
    },
  },
};
