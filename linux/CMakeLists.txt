# The plugin's Linux target.
#
# Flutter Linux builds every plugin with CMake (Swift Package Manager is not
# part of that pipeline), so the Darwin-only Sources/ tree is not used here:
# this target compiles the C++ standard-method-channel implementation against
# the system Tesseract and Leptonica libraries.
#
# This follows the current Flutter plugin template: the plugin is brought in via
# `add_subdirectory` from the app's generated_plugins.cmake, so it must not
# include `ephemeral/generated_plugins.cmake` itself. `apply_standard_settings`
# and the `flutter` target are provided by the including app's ephemeral.

cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "tesseract_ocr")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.10...3.24)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

pkg_check_modules(TESSERACT REQUIRED IMPORTED_TARGET tesseract)
pkg_check_modules(LEPTONICA REQUIRED IMPORTED_TARGET lept)

add_library(${PLUGIN_NAME} SHARED
  "tesseract_ocr_plugin.cc"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  PkgConfig::TESSERACT
  PkgConfig::LEPTONICA)

# Bundled libraries (none — the plugin links the system tesseract).
set(tesseract_ocr_bundled_libraries
  ""
  PARENT_SCOPE
)