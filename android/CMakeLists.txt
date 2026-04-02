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
