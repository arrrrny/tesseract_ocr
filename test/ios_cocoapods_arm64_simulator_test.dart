import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The vendored CocoaPods path must build for `arm64-apple-ios-simulator` with
/// no `EXCLUDED_ARCHS` workaround in the consuming app (issue #51).
///
/// An earlier `SwiftyTesseract401.podspec` depended on `libtesseract`
/// unversioned, which CocoaPods resolved to the unrelated trunk pod
/// `libtesseract` 0.0.2 — a podspec that sets
/// `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` on both the pod target and
/// the user target, so the simulator slice was never built for Apple silicon.
void main() {
  final String root = Directory.current.path;

  String podspec(String name) => File('$root/ios/$name').readAsStringSync();

  /// Whether [contents] assigns a simulator architecture exclusion, e.g.
  /// `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` or
  /// `config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'i386 arm64'`.
  bool excludesSimulatorArch(String contents) {
    final RegExp assignment =
        RegExp(r'''EXCLUDED_ARCHS.*(=>|=)\s*['"]?[^'"]*(i386|arm64|x86_64)''');
    for (final String line in contents.split('\n')) {
      if (assignment.hasMatch(line)) return true;
    }
    return false;
  }

  group('vendored CocoaPods arm64 simulator support', () {
    test('the SwiftyTesseract pod exposes the module name the plugin imports',
        () {
      expect(
        podspec('SwiftyTesseract401.podspec'),
        matches(RegExp(r'''s\.module_name\s*=\s*['"]SwiftyTesseract['"]''')),
        reason: 'ios/Classes and Sources/ guard on canImport(SwiftyTesseract); '
            'a pod named SwiftyTesseract401 builds a module named '
            'SwiftyTesseract401, so the Tesseract engine is never available on '
            'the CocoaPods path',
      );
    });

    test('libtesseract is constrained to the version that ships an arm64 slice',
        () {
      expect(
        podspec('SwiftyTesseract401.podspec'),
        matches(
          RegExp(
              r'''s\.dependency\s+'libtesseract'\s*,\s*['"]>=\s*0\.2\.0['"]'''),
        ),
        reason: 'an unversioned libtesseract dependency resolves to the '
            'unrelated trunk pod libtesseract 0.0.2, whose podspec sets '
            'EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64 on the pod target and '
            'on the user target, so no arm64 simulator module is ever built',
      );
    });

    test('no podspec or Podfile in the repo excludes a simulator architecture',
        () {
      final List<File> files = <File>[
        ...Directory('$root/ios')
            .listSync()
            .whereType<File>()
            .where((File file) => file.path.endsWith('.podspec')),
        File('$root/example/ios/Podfile'),
        File('$root/ios/Podfile'),
      ];

      for (final File file in files) {
        expect(
          excludesSimulatorArch(file.readAsStringSync()),
          isFalse,
          reason: '${file.path} excludes a simulator architecture; the arm64 '
              'simulator slice must build without a workaround in the '
              'consuming app',
        );
      }
    });

    test('every module guarded by canImport is provided by a podspec', () {
      final Set<String> guarded = <String>{};
      final RegExp guard = RegExp(r'''canImport\((\w+)\)''');
      for (final String dir in <String>['ios/Classes', 'Sources']) {
        for (final File file in Directory('$root/$dir')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File file) => file.path.endsWith('.swift'))) {
          for (final RegExpMatch match
              in guard.allMatches(file.readAsStringSync())) {
            guarded.add(match.group(1)!);
          }
        }
      }

      final Set<String> provided = <String>{};
      for (final File file in Directory('$root/ios')
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('.podspec'))) {
        final String contents = file.readAsStringSync();
        provided.add(
          RegExp(r'''s\.name\s*=\s*['"]([^'"]+)['"]''')
              .firstMatch(contents)!
              .group(1)!,
        );
        final RegExpMatch? module =
            RegExp(r'''s\.module_name\s*=\s*['"]([^'"]+)['"]''')
                .firstMatch(contents);
        if (module != null) provided.add(module.group(1)!);
      }

      // SwiftyTesseract is the only third-party module the plugin guards on;
      // it is provided by the custom SwiftyTesseract401 podspec.
      expect(
        guarded.difference(provided),
        isNot(contains('SwiftyTesseract')),
        reason: 'no podspec in ios/ provides the SwiftyTesseract module',
      );
    });
  });
}
