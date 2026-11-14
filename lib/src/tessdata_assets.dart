import 'dart:convert';

import 'package:flutter/services.dart';

/// Packaging rules for the tessdata bundle copy that feeds the native engine.
///
/// Every failure here is a build/packaging mistake the app author can fix, so
/// each one throws an actionable [PlatformException] instead of a raw
/// "Unable to load asset". Failing loudly matters: a tessdata directory that
/// is missing a declared `.traineddata` (or holds a truncated one) makes
/// Tesseract initialize on nothing and return garbage while the path still
/// looks valid — the device-only symptom of issue #52.
class TessDataAssets {
  const TessDataAssets._();

  /// `tessdata_config.json` is absent from the bundle, or unreadable.
  static const String invalidConfigCode = 'tessdata-config-invalid';

  /// A declared `.traineddata` is absent from the bundle, or carries no bytes.
  static const String invalidAssetCode = 'tessdata-asset-invalid';

  /// Parses the `files` list out of `tessdata_config.json`.
  static List<String> parseFileNames(
    String configJson, {
    required String configAsset,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(configJson);
    } on FormatException catch (error) {
      throw _configException(
        configAsset,
        'is not valid JSON (${error.message})',
      );
    }
    if (decoded is! Map) {
      throw _configException(
        configAsset,
        'must be a JSON object with a "files" list',
      );
    }
    final Object? files = (decoded as Map<Object?, Object?>)['files'];
    if (files is! List) {
      throw _configException(
        configAsset,
        'must list every traineddata file in a "files" array of '
        '.traineddata names',
      );
    }
    if (files.isEmpty) {
      throw _configException(
        configAsset,
        'lists no traineddata file — "files" must hold at least one '
        '.traineddata name',
      );
    }
    return files
        .map((Object? file) => _validateFileName(file, configAsset))
        .toList(growable: false);
  }

  /// The asset bundle handed back a traineddata with no bytes.
  static void validateAssetBytes(String assetPath, int byteLength) {
    if (byteLength <= 0) {
      throw PlatformException(
        code: invalidAssetCode,
        message: _assetProblem(assetPath, 'carries no bytes'),
      );
    }
  }

  /// Thrown when the asset bundle cannot produce [assetPath] at all.
  ///
  /// [detail] separates a bundle that carries no such asset from one that could
  /// not be read (a decode failure, an out-of-memory read, a bundle from the
  /// wrong build): a crash report's first sentence should not claim a missing
  /// asset for every one of them.
  static PlatformException unreadableAssetException(
    String assetPath, {
    required Object cause,
    required String detail,
  }) {
    return PlatformException(
      code: invalidAssetCode,
      message: '${_assetProblem(assetPath, detail)}\nCause: $cause',
    );
  }

  /// Whether the destination has to be re-written because [assetBytes] differ
  /// from it.
  ///
  /// A [knownLength] of `null` means this isolate has not read the asset yet, so
  /// only the destination's own length is known — the copy decision is then a
  /// plain length comparison, which an earlier run that died mid-write (or wrote
  /// an empty placeholder) cannot defeat. Once the asset bytes are in hand, the
  /// decision is a real comparison: a same-length file from an older build is
  /// refreshed too, which the length-only test could never see.
  static bool needsCopy({
    required Object? assetBytes,
    required int? knownLength,
    required Uint8List? destinationBytes,
  }) {
    if (assetBytes is Uint8List) {
      if (destinationBytes == null) return true;
      if (destinationBytes.length != assetBytes.length) return true;
      for (int i = 0; i < assetBytes.length; i++) {
        if (destinationBytes[i] != assetBytes[i]) return true;
      }
      return false;
    }
    final int assetLength = knownLength as int;
    return destinationBytes == null || destinationBytes.length != assetLength;
  }

  static String _validateFileName(Object? entry, String configAsset) {
    final String name = entry is String ? entry.trim() : '';
    if (name.isEmpty ||
        name == '.' ||
        name.contains('..') ||
        name.contains('/') ||
        name.contains('\\')) {
      throw _configException(
        configAsset,
        'lists an invalid traineddata file name "$entry" — "files" must hold '
        'plain .traineddata file names, not paths',
      );
    }
    return name;
  }

  static String _assetProblem(String assetPath, String problem) {
    return 'Tesseract tessdata asset "$assetPath" $problem.\n'
        'Declare the config and every traineddata it lists under '
        '"flutter: assets:" in the app\'s pubspec.yaml, e.g.:\n'
        '  assets:\n'
        '    - assets/tessdata_config.json\n'
        '    - assets/tessdata/<lang>.traineddata\n'
        'then rebuild with "flutter clean && flutter pub get && '
        'flutter run --release".';
  }

  static PlatformException _configException(
    String configAsset,
    String problem,
  ) {
    return PlatformException(
      code: invalidConfigCode,
      message: 'Cannot load Tesseract tessdata: "$configAsset" $problem.\n'
          'Declare it under "flutter: assets:" in the app\'s pubspec.yaml:\n'
          '  assets:\n'
          '    - assets/tessdata_config.json\n'
          '    - assets/tessdata/<lang>.traineddata\n'
          'and list every file in its "files" array, e.g. '
          '{"files": ["eng.traineddata"]}.\n'
          'Then rebuild with "flutter clean && flutter pub get".',
    );
  }
}
