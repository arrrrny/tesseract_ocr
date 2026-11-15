# The plugin's Windows target.
#
# Flutter builds every plugin with CMake and MSVC (there is no Swift Package
# Manager or pkg-config on a stock Windows host), so the Tesseract and Leptonica
# dependency has to be located rather than assumed. Two layouts are recognised,
# in this order:
#
#   1. pkg-config — MSYS2 (`pacman -S mingw-w64-x86_64-tesseract`) and the
#      vcpkg tesseract port both export tesseract.pc / lept.pc, which also name
#      the import libraries and the DLLs to bundle.
#   2. TESSERACT_ROOT — the UB-Mannheim installer's prefix (its default is
#      %ProgramFiles%\Tesseract-OCR, and it is honoured from the environment
#      too). That installer ships the import libraries alongside the runtime
#      DLLs, so one directory supplies both the link and the bundle.
#
# When neither layout resolves, the configure step fails with instructions
# rather than producing a plugin DLL that would fail to load at runtime.
#
# This follows the current Flutter Windows plugin template: the plugin is brought
# in via `add_subdirectory` from the app's generated_plugins.cmake, so it must
# not include `ephemeral/generated_plugins.cmake` itself, and
# `apply_standard_settings` plus the `flutter` / `flutter_wrapper_plugin`
# targets are provided by the including app.

cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "tesseract_ocr")
project(${PROJECT_NAME} LANGUAGES CXX)

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "tesseract_ocr_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "tesseract_ocr_plugin.cpp"
  "tesseract_ocr_plugin.h"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/tesseract_ocr/tesseract_ocr_plugin_c_api.h"
  "tesseract_ocr_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# === Tesseract / Leptonica ===

set(TESSERACT_ROOT "" CACHE PATH
    "Tesseract installation prefix (the UB-Mannheim installer's layout)")
if(NOT TESSERACT_ROOT AND DEFINED ENV{TESSERACT_ROOT})
  set(TESSERACT_ROOT "$ENV{TESSERACT_ROOT}")
endif()

set(_tesseract_include_dir "")
set(_tesseract_link_libraries "")
set(_tesseract_bundled_dlls "")

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
  pkg_check_modules(TESSERACT QUIET IMPORTED_TARGET tesseract)
  # Both leptonica spellings are in the wild: the vcpkg port and MSYS2 export
  # lept.pc, other distributions ship leptonica.pc. A port that spells it
  # differently from the one probed here must not read as "not installed".
  pkg_check_modules(LEPTONICA QUIET IMPORTED_TARGET lept)
  if(NOT LEPTONICA_FOUND)
    pkg_check_modules(LEPTONICA QUIET IMPORTED_TARGET leptonica)
  endif()
endif()

if(TESSERACT_FOUND OR LEPTONICA_FOUND)
  if(NOT TESSERACT_FOUND OR NOT LEPTONICA_FOUND)
    # A half-found pkg-config falls through to the prefix probe below — but it
    # must be named, or the FATAL_ERROR at the bottom reads as "the packages
    # the user just installed are missing".
    message(STATUS
      "tesseract_ocr: pkg-config resolved tesseract=${TESSERACT_FOUND} "
      "leptonica=${LEPTONICA_FOUND}; also probing the TESSERACT_ROOT / "
      "install-prefix layout")
  endif()
endif()

if(TESSERACT_FOUND AND LEPTONICA_FOUND)
  # The .pc files carry the include directories and the link interface; the DLLs
  # they were built against sit in the library directories they name.
  list(APPEND _tesseract_link_libraries
    PkgConfig::TESSERACT
    PkgConfig::LEPTONICA)
  set(_pkg_config_dll_dirs "")
  if(TESSERACT_LIBDIR)
    list(APPEND _pkg_config_dll_dirs "${TESSERACT_LIBDIR}")
  endif()
  list(APPEND _pkg_config_dll_dirs
    ${TESSERACT_LIBRARY_DIRS}
    ${LEPTONICA_LIBRARY_DIRS})
  if(TESSERACT_PREFIX)
    list(APPEND _pkg_config_dll_dirs "${TESSERACT_PREFIX}/bin")
  endif()
  if(_pkg_config_dll_dirs)
    list(REMOVE_DUPLICATES _pkg_config_dll_dirs)
    foreach(_dll_dir IN LISTS _pkg_config_dll_dirs)
      file(GLOB _pkg_config_dlls "${_dll_dir}/*.dll")
      list(APPEND _tesseract_bundled_dlls ${_pkg_config_dlls})
    endforeach()
  endif()
  if(NOT _tesseract_bundled_dlls)
    # An empty bundle configures successfully and produces exactly the plugin
    # DLL that fails to load at runtime — the failure the FATAL_ERROR below
    # exists to prevent — so it must be named here, at configure time.
    message(WARNING
      "tesseract_ocr: pkg-config resolved tesseract but no DLLs were found in "
      "the library directories it named; the plugin will fail to load at "
      "runtime. Check TESSERACT_PREFIX or install the runtime DLLs.")
  endif()
  message(STATUS "tesseract_ocr: using the pkg-config tesseract "
                 "(libdirs: ${_pkg_config_dll_dirs})")
else()
  # The UB-Mannheim layout, or any other prefix carrying the same tree.
  #
  # CMake variable names cannot contain the parentheses of `ProgramFiles(x86)`,
  # so the 32-bit prefix is read through the shell instead. It is the location a
  # 32-bit Tesseract installs to even on a 64-bit host, and `ProgramW6432` is
  # only set for a 32-bit process, so it cannot stand in for it.
  set(_tesseract_program_files_x86 "")
  if(WIN32)
    execute_process(COMMAND "$ENV{ComSpec}" /c "echo %ProgramFiles(x86)%"
                    OUTPUT_VARIABLE _tesseract_program_files_x86
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)
    # A shell that did not expand the reference echoes it back verbatim.
    if(_tesseract_program_files_x86 STREQUAL "%ProgramFiles(x86)%")
      set(_tesseract_program_files_x86 "")
    endif()
  endif()

  set(_tesseract_prefix_candidates
    "${TESSERACT_ROOT}"
    "$ENV{ProgramFiles}/Tesseract-OCR"
    "$ENV{ProgramW6432}/Tesseract-OCR"
    "$ENV{LOCALAPPDATA}/Programs/Tesseract-OCR")
  if(_tesseract_program_files_x86)
    list(APPEND _tesseract_prefix_candidates
      "${_tesseract_program_files_x86}/Tesseract-OCR")
  endif()

  set(_tesseract_prefix "")
  foreach(_candidate IN LISTS _tesseract_prefix_candidates)
    if(_candidate AND EXISTS "${_candidate}/include/tesseract/capi.h")
      set(_tesseract_prefix "${_candidate}")
      break()
    endif()
  endforeach()

  if(_tesseract_prefix)
    # Both spellings are in the wild: the UB-Mannheim installer and vcpkg ship
    # `tesseract.lib` / `liblept.lib`, MSYS2 the same names without the `lib`
    # prefix. A debug import library (tesseractd.lib) can sit beside the release
    # one, and linking both would duplicate every symbol, so the sorted first
    # match is the one that is linked.
    file(GLOB _tesseract_import_libraries
      "${_tesseract_prefix}/lib/tesseract*.lib"
      "${_tesseract_prefix}/lib/libtesseract*.lib")
    file(GLOB _leptonica_import_libraries
      "${_tesseract_prefix}/lib/lept*.lib"
      "${_tesseract_prefix}/lib/liblept*.lib")
    file(GLOB _tesseract_runtime_dlls
      "${_tesseract_prefix}/*.dll"
      "${_tesseract_prefix}/bin/*.dll")

    if(_tesseract_import_libraries AND _leptonica_import_libraries)
      list(SORT _tesseract_import_libraries)
      list(SORT _leptonica_import_libraries)
      list(GET _tesseract_import_libraries 0 _tesseract_import_library)
      list(GET _leptonica_import_libraries 0 _leptonica_import_library)

      set(_tesseract_include_dir "${_tesseract_prefix}/include")
      list(APPEND _tesseract_link_libraries
        ${_tesseract_import_library}
        ${_leptonica_import_library})
      list(APPEND _tesseract_bundled_dlls ${_tesseract_runtime_dlls})
      message(STATUS "tesseract_ocr: using the tesseract prefix "
                     "${_tesseract_prefix}")
    else()
      message(STATUS "tesseract_ocr: found Tesseract at ${_tesseract_prefix} "
                     "but not both import libraries (tesseract*.lib and "
                     "liblept*.lib) — install the development files or use "
                     "pkg-config")
    endif()
  endif()
endif()

if(_tesseract_include_dir)
  target_include_directories(${PLUGIN_NAME} PRIVATE
    "${_tesseract_include_dir}")
endif()

if(NOT _tesseract_link_libraries)
  message(FATAL_ERROR
    "tesseract_ocr: Tesseract and Leptonica were not found. Install one of:\n"
    "  - MSYS2:   pacman -S mingw-w64-x86_64-tesseract\n"
    "  - vcpkg:   vcpkg install tesseract (with pkg-config on PATH)\n"
    "  - UB-Mannheim's installer, with its development files, then pass "
    "-DTESSERACT_ROOT=<prefix>\n"
    "The plugin links both libraries and bundles their DLLs next to the "
    "executable.")
endif()

target_link_libraries(${PLUGIN_NAME} PRIVATE ${_tesseract_link_libraries})

# List of absolute paths to libraries that should be bundled with the plugin.
# The app's install step copies them next to the executable, which is how a
# release build finds tesseract's DLLs at runtime.
set(tesseract_ocr_bundled_libraries
  ${_tesseract_bundled_dlls}
  PARENT_SCOPE
)