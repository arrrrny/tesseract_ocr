import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips string literals, char literals and comments from a C++ source so a
/// character count below sees only code — a stray `}` inside a message string
/// must not cancel a missing one in the code around it.
String stripNonCode(String source) {
  final StringBuffer out = StringBuffer();
  var inString = false;
  var inChar = false;
  var inLineComment = false;
  var inBlockComment = false;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (inLineComment) {
      if (c == '\n') {
        inLineComment = false;
        out.write(c);
      }
      continue;
    }
    if (inBlockComment) {
      if (c == '*' && next == '/') {
        i++;
        inBlockComment = false;
      }
      continue;
    }
    if (inString || inChar) {
      if (c == r'\') {
        i++;  // the escaped character does not close the literal
        continue;
      }
      if (inString && c == '"') {
        inString = false;
      } else if (inChar && c == "'") {
        inChar = false;
      }
      continue;
    }
    if (c == '/' && next == '/') {
      inLineComment = true;
      i++;
      continue;
    }
    if (c == '/' && next == '*') {
      inBlockComment = true;
      i++;
      continue;
    }
    if (c == '"') {
      inString = true;
      continue;
    }
    if (c == "'") {
      inChar = true;
      continue;
    }
    out.write(c);
  }
  return out.toString();
}

/// Structural gate for the Windows plugin.
///
/// Windows is the one platform this repository's CI cannot compile (the runner
/// is Linux, and `flutter build windows` needs Visual Studio), so these guards
/// pin the invariants that keep the sources compilable and the plugin actually
/// registered in a host app: the registration symbol the generated
/// `generated_plugins.cmake` calls, the CMake target that has to exist under its
/// exact name, the Tesseract link, and the DLL bundle the app installs next to
/// its executable.
void main() {
  group('Windows plugin source', () {
    late String pubspec;
    late String cmake;
    late String source;
    late String header;
    late String cApiSource;
    late String cApiHeader;

    setUp(() async {
      pubspec = await File('pubspec.yaml').readAsString();
      cmake = await File('windows/CMakeLists.txt').readAsString();
      source = await File('windows/tesseract_ocr_plugin.cpp').readAsString();
      header = await File('windows/tesseract_ocr_plugin.h').readAsString();
      cApiSource =
          await File('windows/tesseract_ocr_plugin_c_api.cpp').readAsString();
      cApiHeader = await File(
        'windows/include/tesseract_ocr/tesseract_ocr_plugin_c_api.h',
      ).readAsString();
    });

    test('pubspec.yaml registers windows as a supported plugin platform',
        () async {
      expect(pubspec, contains('windows:'));
      // `flutter create` emits `<pluginClass>CApi` for a Windows method-channel
      // plugin, and the generated registrant derives both the header it
      // includes and the symbol it calls from exactly this string.
      expect(
        pubspec,
        matches(
          RegExp(
            r'windows:\s*\n\s*pluginClass:\s*TesseractOcrPluginCApi',
          ),
        ),
      );
    });

    test(
        'the C API header declares the registration symbol the registrant calls',
        () async {
      expect(
        cApiHeader,
        contains('TesseractOcrPluginCApiRegisterWithRegistrar'),
      );
      expect(cApiHeader, contains('FlutterDesktopPluginRegistrarRef'));
    });

    test('the C API source defines the registration symbol', () async {
      expect(
        cApiSource,
        contains('TesseractOcrPluginCApiRegisterWithRegistrar'),
      );
      expect(
        cApiSource,
        contains('tesseract_ocr::TesseractOcrPlugin::RegisterWithRegistrar'),
      );
    });

    test('the plugin class registers a method channel named tesseract_ocr',
        () async {
      expect(header, contains('class TesseractOcrPlugin'));
      expect(header, contains('flutter::Plugin'));
      expect(
        source,
        contains('registrar->messenger(), "tesseract_ocr"'),
      );
    });

    test(
        'the plugin answers the methods the Dart layer and the other platforms use',
        () async {
      expect(source, contains('"extractText"'));
      expect(source, contains('"extractHocr"'));
      expect(source, contains('"isSupported"'));
      // extractTextFromBytes sends the image on the channel as imageBytes;
      // the handler must accept it, not answer MISSING_IMAGE_PATH for every
      // bytes call.
      expect(source, contains('"imageBytes"'));
    });

    test('hOCR selects the HOCR reader over the plain-text one', () async {
      // The one behaviour this plugin adds beyond the Linux one — the is_hocr
      // branch must keep reading the right C API entry point.
      expect(
        source,
        contains('is_hocr ? TessBaseAPIGetHOCRText(api, 0)'),
      );
      expect(source, contains('TessBaseAPIGetUTF8Text(api)'));
    });

    test('the plugin rejects the Apple Vision engine instead of running it',
        () async {
      expect(source, contains('"vision"'));
      expect(source, contains('UNSUPPORTED_ENGINE'));
    });

    test('the CMake target keeps the name the generated build rules require',
        () async {
      expect(cmake, contains('set(PLUGIN_NAME "tesseract_ocr_plugin")'));
      expect(cmake, contains(r'add_library(${PLUGIN_NAME} SHARED'));
      expect(
        cmake,
        contains('tesseract_ocr_plugin_c_api.cpp'),
      );
    });

    test('the CMake target links the located Tesseract import libraries',
        () async {
      // The link line must name the variable the discovery above fills —
      // hardcoding a library name here would break every layout the probe
      // supports (pkg-config, TESSERACT_ROOT, the install prefixes).
      expect(
        cmake,
        contains(
          r'target_link_libraries(${PLUGIN_NAME} PRIVATE '
          r'${_tesseract_link_libraries})',
        ),
      );
    });

    test('the CMake finds Tesseract on a Windows host', () async {
      // pkg-config covers MSYS2/vcpkg layouts; TESSERACT_ROOT covers the
      // UB-Mannheim installer, which ships no .pc file.
      expect(cmake, contains('pkg_check_modules'));
      expect(cmake, contains('TESSERACT_ROOT'));
      // The prefix probe keys on the C API header actually shipping with an
      // install — a directory that merely exists must not be accepted.
      expect(cmake, contains('include/tesseract/capi.h'));
      // A missing dependency must stop the build with instructions, never
      // silently produce a plugin that fails to load.
      expect(cmake, contains('FATAL_ERROR'));
    });

    test('the CMake bundles the Tesseract DLLs next to the executable',
        () async {
      expect(cmake, contains('set(tesseract_ocr_bundled_libraries'));
      expect(cmake, contains('PARENT_SCOPE'));
      // The globs that feed the bundle in both layouts — a comment mentioning
      // DLLs must not satisfy this.
      expect(
        cmake,
        contains(r'file(GLOB _pkg_config_dlls "${_dll_dir}/*.dll")'),
      );
      expect(cmake, contains(r'"${_tesseract_prefix}/*.dll"'));
      expect(cmake, contains(r'"${_tesseract_prefix}/bin/*.dll"'));
      // An empty bundle must warn at configure time, not fail at app launch.
      expect(cmake, contains('no DLLs were found'));
    });

    test('the plugin resolves a tessdata directory from the environment',
        () async {
      // The runtime candidates must come from the same environment prefixes
      // the CMake probe reads — a hardcoded C:\ path breaks any other system
      // drive and the per-user install.
      expect(source, contains('ProgramFiles(x86)'));
      expect(source, contains('LOCALAPPDATA'));
      expect(source, contains('"Programs\\\\Tesseract-OCR"'));
      expect(source, contains('tessdata'));
    });

    test('recognition runs off the platform thread', () async {
      // Tesseract blocks for seconds; running it on the platform thread would
      // freeze the app.
      expect(source, contains('std::thread'));
    });

    test('the image path is validated before it reaches the engine', () async {
      expect(source, contains('INVALID_PATH'));
      // The same character set the Linux sibling checks: `%` is a legal
      // Windows filename character and nothing on this call path expands it.
      expect(source, contains(r'find_first_of("\"|;&$`\n\r")'));
    });

    test('the path lookup decodes the UTF-8 bytes that arrived', () async {
      // Paths arrive as UTF-8; a GetFileAttributesA lookup would read them
      // through the ANSI code page and reject every non-ASCII directory.
      expect(source, contains('GetFileAttributesW'));
      expect(source, contains('CP_UTF8'));
    });

    test('the sources are syntactically balanced', () async {
      for (final MapEntry<String, String> entry in <String, String>{
        'windows/tesseract_ocr_plugin.cpp': source,
        'windows/tesseract_ocr_plugin.h': header,
        'windows/tesseract_ocr_plugin_c_api.cpp': cApiSource,
        'windows/include/tesseract_ocr/tesseract_ocr_plugin_c_api.h':
            cApiHeader,
      }.entries) {
        // Count only code: a brace inside a message string or a comment must
        // not cancel a missing one in the code around it.
        final String code = stripNonCode(entry.value);
        for (final List<String> pair in <List<String>>[
          <String>['{', '}'],
          <String>['(', ')'],
          <String>['[', ']'],
        ]) {
          expect(
            code.split(pair[0]).length - 1,
            code.split(pair[1]).length - 1,
            reason: 'unbalanced ${pair[0]}${pair[1]} in ${entry.key}',
          );
        }
      }
    });
  });
}
