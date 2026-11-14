import 'dart:convert';
import 'dart:io';

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
    if (decoded is! Map<String, dynamic>) {
      throw _configException(
        configAsset,
        'must be a JSON object with a "files" list',
      );
    }
    final Object? files = decoded['files'];
    if (files is! List || files.isEmpty) {
      throw _configException(
        configAsset,
        'lists no traineddata file — "files" must hold at least one '
        '.traineddata name',
      );
    }
    return files
        .map((Object? file) => _validateFileName(file?.toString(), configAsset))
        .toList(growable: false);
  }

  /// A traineddata asset the bundle must carry, or the destination that copy
  /// produced — both have to exist and hold bytes.
  static void validateTessDataFile(File file, String assetPath) {
    final int length = file.existsSync() ? file.lengthSync() : -1;
    if (length <= 0) {
      throw PlatformException(
        code: invalidAssetCode,
        message: _assetProblem(
          assetPath,
          'is missing or empty in the tessdata directory '
          '"${file.parent.path}" after the copy from assets',
        ),
      );
    }
  }

  /// The asset bundle handed back a traineddata with no bytes.
  static void validateAssetBytes(String assetPath, int byteLength) {
    if (byteLength <= 0) {
      throw PlatformException(
        code: invalidAssetCode,
        message:
            _assetProblem(assetPath, 'carries no bytes in the asset bundle'),
      );
    }
  }

  /// Whether [assetLength] bytes have to be written over the destination.
  ///
  /// An earlier run that died mid-write (or wrote an empty placeholder) leaves
  /// a file behind; `exists()` alone would keep skipping it forever, so the
  /// destination has to match the asset's length to count as copied.
  static bool needsCopy(
      {required int? existingLength, required int assetLength}) {
    return existingLength == null || existingLength != assetLength;
  }

  /// Thrown when the asset bundle cannot produce [assetPath] at all.
  static PlatformException missingAssetException(
    String assetPath, {
    required Object cause,
  }) {
    return PlatformException(
      code: invalidAssetCode,
      message:
          '${_assetProblem(assetPath, 'is not carried by the asset bundle')}\n'
          'Cause: $cause',
    );
  }

  static String _validateFileName(String? fileName, String configAsset) {
    final String name = fileName?.trim() ?? '';
    if (name.isEmpty || name.contains('..') || name.startsWith('/')) {
      throw _configException(
        configAsset,
        'lists an invalid traineddata file name "$fileName"',
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
