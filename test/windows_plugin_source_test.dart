import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
      expect(source, contains('"isSupported"'));
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

    test('the CMake target links Tesseract and Leptonica', () async {
      expect(cmake, contains('tesseract'));
      expect(cmake, contains('lept'));
    });

    test('the CMake finds Tesseract on a Windows host', () async {
      // pkg-config covers MSYS2/vcpkg layouts; TESSERACT_ROOT covers the
      // UB-Mannheim installer, which ships no .pc file.
      expect(cmake, contains('pkg_check_modules'));
      expect(cmake, contains('TESSERACT_ROOT'));
      // A missing dependency must stop the build with instructions, never
      // silently produce a plugin that fails to load.
      expect(cmake, contains('FATAL_ERROR'));
    });

    test('the CMake bundles the Tesseract DLLs next to the executable',
        () async {
      expect(cmake, contains('set(tesseract_ocr_bundled_libraries'));
      expect(cmake, contains('PARENT_SCOPE'));
      expect(cmake, contains('.dll'));
    });

    test('the plugin resolves a UB-Mannheim tessdata directory', () async {
      expect(source, contains('Tesseract-OCR'));
      expect(source, contains('tessdata'));
    });

    test('recognition runs off the platform thread', () async {
      // Tesseract blocks for seconds; running it on the platform thread would
      // freeze the app.
      expect(source, contains('std::thread'));
    });

    test('the image path is validated before it reaches the engine', () async {
      expect(source, contains('INVALID_PATH'));
    });

    test('the sources are syntactically balanced', () async {
      for (final MapEntry<String, String> entry in <String, String>{
        'windows/tesseract_ocr_plugin.cpp': source,
        'windows/tesseract_ocr_plugin.h': header,
        'windows/tesseract_ocr_plugin_c_api.cpp': cApiSource,
        'windows/include/tesseract_ocr/tesseract_ocr_plugin_c_api.h':
            cApiHeader,
      }.entries) {
        for (final List<String> pair in <List<String>>[
          <String>['{', '}'],
          <String>['(', ')'],
          <String>['[', ']'],
        ]) {
          expect(
            entry.value.split(pair[0]).length - 1,
            entry.value.split(pair[1]).length - 1,
            reason: 'unbalanced ${pair[0]}${pair[1]} in ${entry.key}',
          );
        }
      }
    });
  });
}
