cmake_minimum_required(VERSION 3.13)
project(MediaToolkit)

set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 20)

# ── Find required packages ────────────────────────────────────────────────────
find_package(ReactAndroid REQUIRED)
find_package(fbjni REQUIRED)
find_package(react-native-nitro-modules REQUIRED)

# ── IMPORTANT: create the library target FIRST ───────────────────────────────
# MediaToolkit+autolinking.cmake calls target_sources(MediaToolkit ...) so the
# target must exist before the include() below.
add_library(MediaToolkit SHARED
  # JNI entry point: JVM calls JNI_OnLoad → registers all Nitro HybridObjects
  ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/cpp-adapter.cpp
)

# ── Include nitrogen autolinking (adds sources, headers, link libs) ───────────
# This adds: MediaToolkitOnLoad.cpp, JHybridMediaToolkitSpec.cpp,
#            HybridMediaToolkitSpec.cpp + include dirs + link libraries
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/MediaToolkit+autolinking.cmake)

# ── Workaround: monorepo prefab exposes NitroModules as INTERFACE-only ────────
# In a composite/includeBuild setup the prefab cmake config sets
# INTERFACE_LINK_LIBRARIES to "" (empty), so the actual libNitroModules.so is
# never passed to the linker → undefined symbols for every Nitro core function.
# Fix: locate libNitroModules.so from the local build output by ABI and add it.
get_target_property(_nitro_libs react-native-nitro-modules::NitroModules INTERFACE_LINK_LIBRARIES)
if(NOT _nitro_libs)
  # Resolve the .so path via GLOB (the hash subdir e.g. 2m3q633q changes between builds)
  file(GLOB _nitro_so_candidates
    "${CMAKE_SOURCE_DIR}/../example/node_modules/react-native-nitro-modules/android/build/intermediates/cxx/Debug/*/obj/${ANDROID_ABI}/libNitroModules.so"
  )
  if(_nitro_so_candidates)
    list(GET _nitro_so_candidates 0 _nitro_so)
    message(STATUS "NitroModules prefab INTERFACE-only → linking ${_nitro_so} directly")
    add_library(NitroModulesDirect SHARED IMPORTED)
    set_target_properties(NitroModulesDirect PROPERTIES IMPORTED_LOCATION "${_nitro_so}")
    target_link_libraries(MediaToolkit NitroModulesDirect)
  else()
    message(WARNING "libNitroModules.so not found for ${ANDROID_ABI}, build may fail with undefined symbols")
  endif()
endif()
