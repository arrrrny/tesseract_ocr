import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CocoaPods resolves every podspec file pattern relative to the directory that
/// holds the podspec, so a `:path` pod for `ios/tesseract_ocr.podspec` sees
/// `ios/` as its root. A pattern that matches nothing is not an error at
/// `pod install` time — the pod simply compiles fewer files, and the failure
/// surfaces much later as a missing symbol in the host app.
///
/// That is how the iOS podspec ended up naming `Sources/tesseract_ocr/*.swift`
/// after the Swift plugin moved to the plugin root: the glob resolved to the
/// nonexistent `ios/Sources/tesseract_ocr/`, so the pod compiled only the ObjC
/// shim calling into a class that was never built. These assertions expand the
/// patterns and require at least one real file behind each one.
///
/// Only the plugin's own podspecs are checked. `SwiftyTesseract401.podspec` and
/// `libtesseract.podspec` describe upstream artifacts (a git source and a binary
/// that is not committed), so their patterns cannot resolve in a checkout.
void main() {
  final String root = Directory.current.path;

  /// A minimal glob matcher for the podspec syntax this plugin uses: `*` (one
  /// path segment), `**` (any depth), `?`, and `{a,b}` alternation.
  RegExp globToRegExp(String glob) {
    final StringBuffer pattern = StringBuffer('^');
    for (var i = 0; i < glob.length; i++) {
      final String char = glob[i];
      if (char == '*') {
        if (i + 1 < glob.length && glob[i + 1] == '*') {
          if (i + 2 < glob.length && glob[i + 2] == '/') {
            // Ruby's `**/` also matches zero directories: `Classes/**/*.h`
            // finds `Classes/TesseractOcrPlugin.h`.
            pattern.write('(?:.*/)?');
            i += 2;
          } else {
            pattern.write('.*');
            i++;
          }
        } else {
          pattern.write('[^/]*');
        }
      } else if (char == '?') {
        pattern.write('[^/]');
      } else if (char == '{') {
        final int end = glob.indexOf('}', i);
        expect(end, greaterThan(i), reason: 'unbalanced brace in glob $glob');
        final String alternatives =
            glob.substring(i + 1, end).split(',').map(RegExp.escape).join('|');
        pattern.write('(?:$alternatives)');
        i = end;
      } else {
        pattern.write(RegExp.escape(char));
      }
    }
    pattern.write(r'$');
    return RegExp(pattern.toString());
  }

  /// The patterns of one podspec attribute, in podspec order. Collection stops
  /// at the next `s.<attribute> =` line so a following attribute's values (a
  /// resource bundle name, say) are never read as file patterns.
  List<String> patternsOf(String podspec, String attribute) {
    final List<String> patterns = <String>[];
    var collecting = false;
    for (final String line in podspec.split('\n')) {
      final String trimmed = line.trim();
      if (!collecting) {
        if (RegExp('^$attribute\\s*=').hasMatch(trimmed)) {
          collecting = true;
        } else {
          continue;
        }
      } else if (trimmed.startsWith('s.') || trimmed == 'end') {
        break;
      }
      for (final RegExpMatch match
          in RegExp(r"""['"]([^'"]+)['"]""").allMatches(line)) {
        final String value = match.group(1)!;
        if (!value.startsWith('-')) {
          patterns.add(value);
        }
      }
    }
    return patterns;
  }

  final List<File> podspecs = <File>[
    File('$root/ios/tesseract_ocr.podspec'),
    File('$root/macos/tesseract_ocr.podspec'),
  ];

  /// The checkout files a podspec pattern can resolve against: the shared
  /// `Sources/` tree both Apple pods reach through `../`, plus each podspec's
  /// own directory. Walking the repo root instead walks `.git` and any `build/`
  /// tree to answer a glob question about two directories.
  final List<String> files = <String>[];
  for (final Directory directory in <Directory>[
    Directory('$root/Sources'),
    ...podspecs.map((File podspec) => podspec.parent),
  ]) {
    if (!directory.existsSync()) continue;
    files.addAll(
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .map((File file) => file.path),
    );
  }

  for (final File podspec in podspecs) {
    test('${podspec.uri.pathSegments.last} patterns resolve to real files', () {
      final String contents = podspec.readAsStringSync();
      final Directory podRoot = podspec.parent;

      for (final String attribute in <String>[
        's.source_files',
        's.public_header_files',
      ]) {
        for (final String pattern in patternsOf(contents, attribute)) {
          // CocoaPods joins the pattern to the podspec directory; a leading `../`
          // escapes it, which is how both Apple pods reach the shared Sources/
          // tree without copying it.
          final String joined = pattern.startsWith('../')
              ? '${podRoot.parent.path}/${pattern.substring(3)}'
              : '${podRoot.path}/$pattern';
          final RegExp matcher = globToRegExp(joined);
          final bool matches = files.any(matcher.hasMatch);
          expect(
            matches,
            isTrue,
            reason: '$attribute pattern "$pattern" matches no file under '
                '${podRoot.path}. CocoaPods resolves it against the podspec '
                'directory, so the pod would compile nothing there.',
          );
        }
      }
    });
  }

  test('both Apple pods compile the shared Swift source', () {
    expect(
      File('$root/Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift')
          .existsSync(),
      isTrue,
    );
    for (final File podspec in podspecs) {
      expect(
        patternsOf(podspec.readAsStringSync(), 's.source_files'),
        contains('../Sources/tesseract_ocr/*.swift'),
        reason: '${podspec.path} must compile the shared plugin source',
      );
    }
  });
}