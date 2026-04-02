cmake_minimum_required(VERSION 3.13)
project(MediaToolkit)

set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 20)

# ── React Native setup ────────────────────────────────────────────────────────
find_package(ReactAndroid REQUIRED)
find_package(fbjni REQUIRED)
find_package(react-native-nitro-modules REQUIRED)

# ── Nitrogen generated autolinking (sources + headers + definitions) ──────────
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/MediaToolkit+autolinking.cmake)

# ── C++ library ──────────────────────────────────────────────────────────────
add_library(
  MediaToolkit
  SHARED
  # Library C++ sources (none needed — all logic is in Kotlin via JNI)
)

# Apply nitrogen-generated sources/includes/definitions to the library target
target_include_directories(MediaToolkit PRIVATE
  "${CMAKE_SOURCE_DIR}/../nitrogen/generated/shared/c++"
  "${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/c++"
  "${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/"
)
