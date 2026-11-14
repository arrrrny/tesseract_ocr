import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS Vision plugin is registered as a Flutter method-call delegate, so
/// `handle(_:result:)` runs on the platform (main) thread. A
/// `VNImageRequestHandler.perform` call made there keeps the main thread busy
/// for the whole recognition, which freezes the UI.
///
/// There is no XCTest target for the iOS sources (the example app's
/// `RunnerTests` folder is not part of `Runner.xcodeproj`), so these tests pin
/// the threading contract against the plugin source itself.
void main() {
  final VisionPluginSource plugin = VisionPluginSource.read();

  test('recognition is dispatched off the platform thread', () {
    final Block? recognition = plugin.recognition;

    expect(
      recognition,
      isNotNull,
      reason: 'the recognition call must sit inside a DispatchQueue .async '
          'block',
    );
    expect(
      recognition!.receiver,
      isNot(contains('main')),
      reason: 'handle() runs on the platform thread, so the recognition must '
          'be dispatched off it',
    );
  });

  test('recognition answers are delivered on the main thread', () {
    final List<Block> offPlatform = plugin.offPlatformRegions;
    expect(
      offPlatform,
      isNotEmpty,
      reason: 'the recognition must answer from off the platform thread',
    );

    var answers = 0;
    for (final Block region in offPlatform) {
      for (final int answer in plugin.answerCalls(region)) {
        answers++;
        expect(
          plugin.isOnMainQueue(answer),
          isTrue,
          reason: 'a recognition that runs off the main thread — the request '
              'completion on Vision\'s queue, or the dispatched perform — must '
              'hop back to the main queue before calling FlutterResult',
        );
      }
    }

    expect(
      answers,
      greaterThan(0),
      reason: 'the completion and the thrown perform error must both be able '
          'to answer, and a second FlutterResult call crashes the app',
    );
  });
}

/// The `performVisionOCR` source, parsed only as far as the threading
/// questions below need: where a call site sits relative to a block, and
/// whether it is reached through a `DispatchQueue.main.async` block.
class VisionPluginSource {
  VisionPluginSource._(this.source);

  /// The plugin source, read from the repo root.
  ///
  /// `flutter test` — the repo's gate (`.github/workflows/ci.yml`) — runs with
  /// the package root as its cwd, the same assumption the other source-reading
  /// tests in this repo make. The explicit check makes a run from another cwd
  /// fail naming the path it looked for instead of a bare
  /// `PathNotFoundException` on a relative file.
  factory VisionPluginSource.read() {
    const String path = 'Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift';
    final File file = File(path);
    if (!file.existsSync()) {
      fail('cannot read $path from ${Directory.current.path}: run the suite '
          'from the package root');
    }
    return VisionPluginSource._(file.readAsStringSync());
  }

  final String source;

  /// [source] with every comment and string literal blanked out, offsets
  /// preserved.
  ///
  /// A brace inside a comment or a string (`print("{}")`, a `// try { … }`)
  /// would otherwise truncate a block, and every assertion built on that block
  /// would silently degrade to null on a correct implementation.
  late final String masked = _maskNonCode(source);

  /// The `DispatchQueue … .async { … }` block that encloses the recognition
  /// call, or null when the call is not dispatched at all.
  late final Block? recognition = _enclosingAsyncBlock(
    masked.indexOf('requestHandler.perform'),
  );

  /// The blocks the recognition answers from, both of which run off the
  /// platform thread: the `VNRecognizeTextRequest` completion (Vision calls it
  /// on its own queue) and the dispatched perform (a global queue, plus its
  /// `catch`). The synchronous image-load guard before them is not here: it
  /// answers on the platform thread already.
  late final List<Block> offPlatformRegions = <Block>[
    if (recognition != null) recognition!,
    if (requestCompletion != null) requestCompletion!,
  ];

  /// The `VNRecognizeTextRequest { … }` completion, as a block, or null when
  /// the file does not declare one.
  late final Block? requestCompletion = _trailingClosureOf(
    'VNRecognizeTextRequest',
  );

  /// Whether [index] sits inside a `DispatchQueue.main.async { … }` block.
  bool isOnMainQueue(int index) {
    return _enclosing(index, 'DispatchQueue.main') != null;
  }

  /// Offsets of every `result(…)` call inside [block].
  List<int> answerCalls(Block block) {
    final List<int> calls = <int>[];
    for (final RegExpMatch match
        in RegExp(r'\bresult\s*\(').allMatches(masked)) {
      if (match.start > block.start && match.start < block.end) {
        calls.add(match.start);
      }
    }
    return calls;
  }

  /// The block whose body contains [index], as the receiver it is sent to and
  /// its offsets, or null.
  Block? _enclosing(int index, [String? receiverPrefix]) {
    if (index < 0) return null;
    for (final RegExpMatch match
        in RegExp(r'\.async\s*\{').allMatches(masked)) {
      if (receiverPrefix != null &&
          !masked.substring(0, match.start).endsWith(receiverPrefix)) {
        continue;
      }
      final ({int start, int end})? block = _bracedBlock(masked, match.end - 1);
      if (block == null) continue;
      if (block.start < index && index < block.end) {
        final int lineStart = masked.lastIndexOf('\n', match.start) + 1;
        return (
          receiver: source.substring(lineStart, match.start).trim(),
          start: block.start,
          end: block.end,
        );
      }
    }
    return null;
  }

  /// The `.async { … }` block that encloses [index] — any receiver.
  Block? _enclosingAsyncBlock(int index) => _enclosing(index);

  /// The `{ … }` block of the named trailing closure (for example
  /// `VNRecognizeTextRequest { … }`).
  Block? _trailingClosureOf(String name) {
    final int declaration = masked.indexOf(name);
    if (declaration < 0) return null;
    final int openBrace = masked.indexOf('{', declaration + name.length);
    if (openBrace < 0) return null;
    final ({int start, int end})? block = _bracedBlock(masked, openBrace);
    if (block == null) return null;
    return (receiver: name, start: block.start, end: block.end);
  }
}

/// A `{ … }` block of interest: the receiver it is sent to, and its (start,
/// end) offsets into the source.
typedef Block = ({String receiver, int start, int end});

/// The `{ … }` block opened at [openBrace] in [source], as (start, end)
/// offsets of its body, or null when it is never closed.
///
/// [source] must already be masked (see [VisionPluginSource.masked]): a brace
/// inside a string or a comment must not close a block.
({int start, int end})? _bracedBlock(String source, int openBrace) {
  if (openBrace < 0 || openBrace >= source.length || source[openBrace] != '{') {
    return null;
  }
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final String char = source[i];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return (start: openBrace + 1, end: i);
    }
  }
  return null;
}

/// [source] with comments and string literals replaced by spaces, so a brace or
/// keyword scan cannot be derailed by either. Newlines are kept, so offsets
/// and line numbers are unchanged and masked text can be sliced against
/// [source].
String _maskNonCode(String source) {
  final List<String> chars = source.split('');

  void blank(int start, int end) {
    for (var i = start; i < end && i < chars.length; i++) {
      if (chars[i] != '\n') chars[i] = ' ';
    }
  }

  var i = 0;
  while (i < source.length) {
    final String char = source[i];
    if (char == '/' && i + 1 < source.length && source[i + 1] == '/') {
      final int newline = source.indexOf('\n', i);
      final int end = newline < 0 ? source.length : newline;
      blank(i, end);
      i = end;
      continue;
    }
    if (char == '/' && i + 1 < source.length && source[i + 1] == '*') {
      // Swift nests block comments, so they cannot be closed at the first */
      var depth = 1;
      var end = i + 2;
      while (end < source.length && depth > 0) {
        if (source.startsWith('/*', end)) {
          depth++;
          end += 2;
        } else if (source.startsWith('*/', end)) {
          depth--;
          end += 2;
        } else {
          end++;
        }
      }
      blank(i, end);
      i = end;
      continue;
    }
    if (char == '"') {
      final int end = _stringEnd(source, i);
      blank(i, end);
      i = end;
      continue;
    }
    i++;
  }
  return chars.join();
}

/// The offset just past the string literal opened at [start], or the end of
/// [source] when it is never closed.
int _stringEnd(String source, int start) {
  final bool multiline = source.startsWith('"""', start);
  final String delimiter = multiline ? '"""' : '"';
  var i = start + delimiter.length;
  while (i < source.length) {
    if (source.startsWith(delimiter, i)) return i + delimiter.length;
    // An unterminated single-line string ends at its newline.
    if (!multiline && source[i] == '\n') return i;
    if (source.startsWith('\\(', i)) {
      i = _interpolationEnd(source, i + 2);
      continue;
    }
    if (source[i] == '\\') {
      i += 2;
      continue;
    }
    i++;
  }
  return source.length;
}

/// The offset just past the `)` that closes the string interpolation whose
/// contents start at [start].
int _interpolationEnd(String source, int start) {
  var depth = 1;
  var i = start;
  while (i < source.length && depth > 0) {
    final String char = source[i];
    if (char == '"') {
      i = _stringEnd(source, i);
      continue;
    }
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
    }
    i++;
  }
  return i;
}
