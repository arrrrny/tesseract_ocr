import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// macOS plugin source gate.
///
/// Nothing in this repo compiles a macOS pod, and that is a property of the host,
/// not an omission: `pod install` in `example/macos` needs
/// `libtesseract.xcframework`, a binary that is deliberately not committed, and a
/// plain `swift build` cannot resolve the Flutter engine module.
///
/// What these assertions do is pin the structural properties that keep the macOS
/// source compilable in the host app:
///
/// * Flutter resolves the macOS plugin through `macos/tesseract_ocr.podspec` — the
///   `darwin/` layout a `sharedDarwinSource` flag would demand does not exist here.
/// * That podspec compiles the SAME shared Swift source as iOS, so macOS cannot
///   drift into a second implementation again.
/// * The generated plugin registrant imports `TesseractOcrPlugin`; the ObjC shim
///   provides that name and forwards it to the shared Swift class.
/// * The `tesseract` executable is no longer spawned anywhere on macOS.
void main() {
  final String root = Directory.current.path;

  String read(String path) => File('$root/$path').readAsStringSync();

  group('macOS podspec', () {
    test('compiles the shared Apple source instead of a macOS-only copy', () {
      final String podspec = read('macos/tesseract_ocr.podspec');
      expect(podspec, contains("'../Sources/tesseract_ocr/*.swift'"));
      expect(podspec, isNot(contains("'tesseract_ocr/Sources")));
    });

    test('declares the pods macOS needs', () {
      final String podspec = read('macos/tesseract_ocr.podspec');
      expect(podspec, contains("s.dependency 'FlutterMacOS'"));
      expect(podspec, contains("s.dependency 'SwiftyTesseract401'"));
      expect(podspec, isNot(contains("s.dependency 'Flutter'")));
    });

    test("keeps the macOS deployment target the SPM manifest promises (10.13)",
        () {
      expect(read('macos/tesseract_ocr.podspec'),
          contains("s.platform = :osx, '10.13'"));
    });

    test('compiles the ObjC shim that carries the registrant class name', () {
      final String podspec = read('macos/tesseract_ocr.podspec');
      expect(podspec, contains("s.source_files     = 'Classes/*.{h,m,mm}'"));
      expect(podspec, contains("s.public_header_files = 'Classes/**/*.h'"));
      expect(File('$root/macos/Classes/TesseractOcrPlugin.h').existsSync(), isTrue);
    });
  });

  group('macOS implementation', () {
    test('the shim forwards registration to the shared Swift plugin', () {
      final String header = read('macos/Classes/TesseractOcrPlugin.h');
      final String shim = read('macos/Classes/TesseractOcrPlugin.m');
      expect(header, contains('#import <FlutterMacOS/FlutterMacOS.h>'));
      expect(header, contains('@interface TesseractOcrPlugin : NSObject<FlutterPlugin>'));
      expect(shim, contains('#import <tesseract_ocr/tesseract_ocr-Swift.h>'));
      expect(
        shim,
        contains('[SwiftTesseractOcrPlugin registerWithRegistrar:registrar]'),
      );
    });

    test('the shared source imports the macOS engine module on macOS', () {
      final String source =
          read('Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift');
      expect(source, contains('#if canImport(FlutterMacOS)\nimport FlutterMacOS'));
      // The iOS build of the same file must still import `Flutter`.
      expect(source, contains('#else\nimport Flutter\n#endif'));
    });

    test('no macOS source spawns the tesseract executable', () {
      const List<String> sourceExtensions = ['.swift', '.m', '.mm'];
      final List<File> sources = Directory('$root/macos')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) =>
              sourceExtensions.any(file.path.endsWith))
          .toList();
      expect(sources, isNotEmpty,
          reason: 'the macOS plugin directory must still hold source files');

      for (final File file in sources) {
        expect(
          file.readAsStringSync(),
          isNot(contains('Process()')),
          reason: '${file.path} must not drive the command-line tesseract: macOS '
              'runs the shared in-process engine',
        );
      }
    });

    test('the legacy macOS-only plugin and its SwiftPM manifest are gone', () {
      expect(
        File(
          '$root/macos/tesseract_ocr/Sources/tesseract_ocr/TesseractOcrPlugin.swift',
        ).existsSync(),
        isFalse,
        reason: 'the Process-based macOS plugin was replaced by the shared source',
      );
      expect(
        File('$root/macos/tesseract_ocr/Package.swift').existsSync(),
        isFalse,
        reason: 'SwiftPM cannot compile a target whose sources live outside the '
            'package root, so macOS shares the source through its podspec',
      );
      expect(
        File('$root/macos/Resources/PrivacyInfo.xcprivacy').existsSync(),
        isTrue,
        reason: 'the macOS pod still bundles its privacy manifest',
      );
    });
  });

  group('custom podspecs', () {
    test('SwiftyTesseract401 builds on macOS with AppKit instead of UIKit', () {
      final String podspec = read('ios/SwiftyTesseract401.podspec');
      expect(podspec, contains("s.osx.deployment_target = '10.13'"));
      expect(podspec, contains("s.ios.frameworks = 'Foundation', 'UIKit'"));
      expect(podspec, contains("s.osx.frameworks = 'Foundation', 'AppKit'"));
      // A single unscoped `s.frameworks` would link UIKit into the macOS build.
      expect(
        podspec,
        isNot(matches(RegExp(r'^\s*s\.frameworks\s*=', multiLine: true))),
      );
    });

    test('libtesseract builds on macOS too', () {
      expect(read('ios/libtesseract.podspec'),
          contains("s.osx.deployment_target = '10.13'"));
    });
  });

  group('example macOS app', () {
    test('has a Podfile that installs the plugin pods', () {
      final String podfile = read('example/macos/Podfile');
      expect(podfile, contains("platform :osx, '10.13'"));
      expect(
        podfile,
        contains(
          "pod 'SwiftyTesseract401', :podspec => '../../ios/SwiftyTesseract401.podspec'",
        ),
      );
      expect(podfile, contains("pod 'libtesseract', :path => '../../ios'"));
      expect(podfile, contains('flutter_install_all_macos_pods'));
    });
  });
}