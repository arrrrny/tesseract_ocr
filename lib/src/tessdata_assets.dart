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

  /// A caller-supplied tessdata directory holds no `.traineddata` for the
  /// requested language.
  ///
  /// Distinct from [invalidAssetCode]: the bundle is not involved at all here,
  /// so the actionable fix is to put the file on the device — not to declare an
  /// asset.
  static const String invalidPathCode = 'tessdata-path-invalid';

  /// The subdirectory a tessdata parent keeps its `.traineddata` files in.
  static const String tessdataDirectoryName = 'tessdata';

  /// The extension every traineddata file carries.
  static const String trainedDataExtension = '.traineddata';

  /// The `+`-separated language parts of a Tesseract language string.
  ///
  /// `'eng+deu'` asks the engine for two traineddata files, so every part has to
  /// resolve before a tessdata directory can be called usable.
  static List<String> languageParts(String language) {
    return language
        .split('+')
        .map((String part) => part.trim())
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
  }

  /// The `.traineddata` file name of [languagePart].
  static String trainedDataFile(String languagePart) {
    return '$languagePart$trainedDataExtension';
  }

  /// Thrown when [path] is not a tessdata directory the engine can read.
  ///
  /// [missingFiles] is the set the request needs, whether the directory was
  /// absent or merely incomplete: the caller's next step is the same either way.
  static PlatformException pathException({
    required String path,
    required String language,
    required List<String> missingFiles,
  }) {
    final List<String> parts = languageParts(language);
    final String example = parts.isEmpty ? 'eng' : parts.first;
    return PlatformException(
      code: invalidPathCode,
      message: 'Cannot load Tesseract tessdata: "$path" holds no '
          'traineddata file for language "$language" '
          '(missing ${missingFiles.join(', ')}).\n'
          'Tesseract reads a directory of .traineddata files, either '
          'directly:\n'
          '  $path/$example$trainedDataExtension\n'
          'or under a "$tessdataDirectoryName" subdirectory:\n'
          '  $path/$tessdataDirectoryName/$example$trainedDataExtension\n'
          'Download the missing .traineddata file(s) into that directory '
          '(e.g. from github.com/tesseract-ocr/tessdata_fast) and pass it as '
          'OCRConfig(tessDataPath: ...), or drop the override to use the '
          'bundled assets/tessdata/ set.',
    );
  }

  /// Thrown when a `.traineddata` the request needs is present in [path] but
  /// carries no bytes.
  ///
  /// Distinct from [pathException]: the file is there under its own name, so
  /// "download the missing files" would be the wrong instruction — a truncated
  /// download sits exactly here and has to be deleted and fetched again.
  static PlatformException emptyFilesException({
    required String path,
    required List<String> files,
  }) {
    return PlatformException(
      code: invalidPathCode,
      message: 'Cannot load Tesseract tessdata: "$path" holds an empty '
          '.traineddata file the requested language needs '
          '(${files.join(', ')} — 0 bytes).\n'
          'A truncated download lands exactly here: delete the listed '
          '.traineddata file(s) and download them again (e.g. from '
          'github.com/tesseract-ocr/tessdata_fast), or drop the override to '
          'use the bundled assets/tessdata/ set.',
    );
  }

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
