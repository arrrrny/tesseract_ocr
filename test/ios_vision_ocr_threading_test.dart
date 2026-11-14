import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS Vision plugin is registered as a Flutter method-call delegate, so
/// `handle(_:result:)` runs on the platform (main) thread. A
/// `VNImageRequestHandler.perform` call made there keeps the main thread busy
/// for the whole recognition, which freezes the UI.
///
/// There is no XCTest target for the iOS sources (the example app's
/// `RunnerTests` folder is not part of `Runner.xcodeproj`), so this test pins
/// the threading contract against the plugin source itself.
void main() {
  final pluginFile = File('ios/Classes/SwiftTesseractOcrPlugin.swift');

  test('the iOS Vision plugin source is present', () {
    expect(
      pluginFile.existsSync(),
      isTrue,
      reason: '${pluginFile.path} is the iOS Vision plugin implementation',
    );
  });

  test('recognition is dispatched off the platform thread', () {
    final source = pluginFile.readAsStringSync();
    final recognition =
        _enclosingAsyncBlock(source, source.indexOf('perform('));

    expect(
      recognition,
      isNotNull,
      reason:
          'the recognition call must sit inside a DispatchQueue .async block',
    );
    expect(
      recognition!.receiver,
      isNot(contains('main')),
      reason:
          'handle() runs on the platform thread, so the recognition must be '
          'dispatched off it',
    );
  });

  test('recognition results are delivered on the main thread', () {
    final source = pluginFile.readAsStringSync();
    final recognition = _enclosingAsyncBlock(
      source,
      source.indexOf('perform('),
    );

    expect(recognition, isNotNull);
    expect(
      recognition!.body,
      contains('DispatchQueue.main.async'),
      reason:
          'the completion runs off the main thread and must hop back before '
          'answering the method channel',
    );
  });

  test('the recognition is answered exactly once', () {
    final source = pluginFile.readAsStringSync();
    final recognition = _enclosingAsyncBlock(
      source,
      source.indexOf('perform('),
    );

    expect(recognition, isNotNull);
    expect(
      recognition!.body,
      contains('completeOnce'),
      reason:
          'the completion handler and a thrown error can both answer, and a '
          'second FlutterResult call crashes the app',
    );
  });
}

/// The `.async { … }` block whose body contains [index], as the receiver it is
/// sent to and its body text, or null.
({String receiver, String body})? _enclosingAsyncBlock(
    String source, int index) {
  if (index < 0) return null;
  for (final match in RegExp(r'\.async\s*\{').allMatches(source)) {
    final block = _bracedBlock(source, match.end - 1);
    if (block == null) continue;
    if (block.start < index && index < block.end) {
      final lineStart = source.lastIndexOf('\n', match.start) + 1;
      return (
        receiver: source.substring(lineStart, match.start).trim(),
        body: source.substring(block.start, block.end),
      );
    }
  }
  return null;
}

/// The `{ … }` block opened at [openBrace], as (start, end) offsets of its body.
({int start, int end})? _bracedBlock(String source, int openBrace) {
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final char = source.codeUnitAt(i);
    if (char == 0x7B) {
      depth++;
    } else if (char == 0x7D) {
      depth--;
      if (depth == 0) return (start: openBrace + 1, end: i);
    }
  }
  return null;
}
