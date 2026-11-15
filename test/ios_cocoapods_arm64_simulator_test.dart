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

  /// Every `.podspec` in the repo, recursively, plus the plugin's own
  /// per-platform Podfiles and every `example/*/ios/Podfile`.
  ///
  /// A podspec nested under `ios/Sub/` is as reachable as a top-level one —
  /// CocoaPods resolves a plugin podspec by name from the platform directory —
  /// so the scan must be recursive.
  List<File> scannedFiles() => <File>[
        ...Directory('$root/ios')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File file) => file.path.endsWith('.podspec')),
        ...Directory('$root/macos')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File file) => file.path.endsWith('.podspec')),
        ...Directory('$root/example')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File file) =>
                file.parent.path.endsWith('/ios') &&
                file.path.endsWith('/Podfile')),
        File('$root/ios/Podfile'),
      ];

  /// Whether [contents] assigns a simulator architecture exclusion, e.g.
  /// `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` or
  /// `config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'i386 arm64'`.
  ///
  /// The assignment's VALUE is what is inspected, so a multi-line Ruby array
  /// (`EXCLUDED_ARCHS = [\n  'arm64',\n]`) is matched as readily as a single
  /// quoted string, and a `#` comment beside either is ignored. An
  /// `EXCLUDED_ARCHS` that excludes only device architectures (a real setting
  /// for some pods) is left alone: only the simulator exclusion is this issue's
  /// defect.
  bool excludesSimulatorArch(String contents) {
    final List<String> lines =
        contents.split('\n').where((String line) => !line.trimLeft().startsWith('#')).toList();

    for (int index = 0; index < lines.length; index++) {
      final RegExpMatch? match =
          RegExp(r'''EXCLUDED_ARCHS[^\n]*(?:=>|=)''').firstMatch(lines[index]);
      if (match == null) continue;

      // Collect the assigned value until the Ruby expression ends (a closing
      // bracket, a `}`, or the end of the line).
      final StringBuffer value = StringBuffer(lines[index].substring(match.end));
      for (int cursor = index + 1;
          value.toString().contains(RegExp(r'''[\[\{]\s*$''')) &&
              cursor < lines.length;
          cursor++) {
        value.write('\n');
        value.write(lines[cursor]);
      }

      final String scalar = value
          .toString()
          .replaceAll(RegExp(r'''\[[^\]]*\]'''), '')
          .replaceAll(RegExp(r'''\{[^}]*\}'''), '');
      if (scalar.contains(RegExp(r'''(i386|arm64|x86_64)'''))) return true;
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

    test('libtesseract is constrained to the 0.2.x line that ships an arm64 slice',
        () {
      expect(
        podspec('SwiftyTesseract401.podspec'),
        matches(
          RegExp(
              r'''s\.dependency\s+'libtesseract'\s*,\s*['"]~>\s*0\.2\.0['"]'''),
        ),
        reason: 'an unversioned libtesseract dependency resolves to the '
            'unrelated trunk pod libtesseract 0.0.2, whose podspec sets '
            'EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64 on the pod target and '
            'on the user target, so no arm64 simulator module is ever built; an '
            'open-ended pin would also let a future 0.3/1.0 change the binary '
            'contract this pod pinned down',
      );
    });

    test('the local libtesseract pod fails loudly when its binary is absent',
        () {
      final String libtesseract = podspec('libtesseract.podspec');
      final bool binaryPresent =
          File('$root/ios/libtesseract.xcframework').existsSync();

      // The binary is not shipped in the repo: the consumer places it in the
      // PLUGIN's ios/ directory (the pod is consumed by :path from there).
      if (binaryPresent) return;

      expect(
        libtesseract,
        matches(RegExp(r'''raise\b''')),
        reason: 'CocoaPods silently drops a vendored framework it cannot find, '
            'so a missing xcframework surfaces as a link or '
            "'Couldn't find module' error far from its cause; libtesseract."
            'podspec must raise instead',
      );

      // The podspec must resolve the framework beside itself — not from the
      // consuming app's ios/ directory, which is where the READMEs used to
      // tell the user to put it.
      expect(
        libtesseract,
        matches(RegExp(r'''__dir__''')),
        reason: 'libtesseract.podspec must resolve libtesseract.xcframework '
            'relative to the plugin directory (__dir__), because CocoaPods '
            'consumes the pod from <plugin>/ios by :path',
      );
    });

    test('no podspec or Podfile in the repo excludes a simulator architecture',
        () {
      final List<File> files = scannedFiles();

      expect(files, isNotEmpty, reason: 'no podspec or Podfile found to scan');

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
          .listSync(recursive: true)
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

      // Swift/ObjC modules the platform itself provides are not pods, so they
      // are outside what a podspec could ever provide. `FlutterMacOS` is the
      // macOS engine module (the shared Swift source picks between it and
      // `Flutter` by canImport).
      final Set<String> systemModules = <String>{
        'UIKit',
        'AppKit',
        'Foundation',
        'Flutter',
        'FlutterMacOS',
        'Vision',
      };
      final Set<String> missing =
          guarded.difference(provided).difference(systemModules);

      expect(
        missing,
        isEmpty,
        reason: 'no podspec in ios/ provides the guarded module(s) '
            '${missing.join(', ')}',
      );
    });
  });
}