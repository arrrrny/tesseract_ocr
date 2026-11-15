import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tesseract_ocr/src/tessdata_assets.dart';

Future<bool> fileExists(String path) => File(path).exists();

/// Resolves a caller-supplied tessdata directory to the directory that holds the
/// requested languages' `.traineddata` (issue #56).
///
/// A download-on-demand flow points recognition at a directory already on the
/// device, and that directory comes in either layout: the `.traineddata` files
/// sit in it directly, or it is a parent carrying the `tessdata/`
/// subdirectory the bundled asset copy produces. Both resolve to the directory
/// the engine reads, so a downloaded set and a bundled set behave identically.
///
/// Anything else throws [PlatformException] naming [path]: the native engine's
/// own `TESSDATA_NOT_FOUND` sends the caller back to declaring Flutter assets,
/// which is exactly the step this flow exists to skip.
Future<String> resolveTessDataDirectory(
  String path, {
  required String language,
}) async {
  final String trimmed = path.trim();
  final List<String> parts = TessDataAssets.languageParts(language);
  final List<String> wanted = (parts.isEmpty ? <String>['eng'] : parts)
      .map(TessDataAssets.trainedDataFile)
      .toList(growable: false);

  if (trimmed.isNotEmpty) {
    for (final String candidate in <String>[
      trimmed,
      join(trimmed, TessDataAssets.tessdataDirectoryName),
    ]) {
      final List<String>? present = await _trainedDataFiles(candidate);
      if (present == null) continue;
      final bool complete = wanted.every(present.contains);
      if (complete) return candidate;
    }
  }

  throw TessDataAssets.pathException(
    path: trimmed,
    language: language,
    missingFiles: wanted,
  );
}

/// The `.traineddata` names in directory [path], or null when [path] is not a
/// directory this isolate can list.
///
/// A null return is "no such directory", never an error to raise: a missing
/// directory and a directory without the file are the same actionable outcome,
/// and only one of them is worth a stack trace.
Future<List<String>?> _trainedDataFiles(String path) async {
  final Directory directory = Directory(path);
  try {
    final FileStat stats = await directory.stat();
    if (stats.type != FileSystemEntityType.directory) return null;
    final List<String> names = <String>[];
    await for (final FileSystemEntity entity in directory.list(
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final String name = basename(entity.path);
      if (name.endsWith(TessDataAssets.trainedDataExtension)) {
        names.add(name);
      }
    }
    return names;
  } on Object {
    return null;
  }
}

/// The tessdata set this isolate already resolved from the asset bundle.
///
/// Asset bytes are immutable for the life of a process and
/// `CachingAssetBundle` caches `loadString` but NOT `load` (the binary read —
/// see `packages/flutter/lib/src/services/asset_bundle.dart`), so without this
/// cache every `extractText` call would re-read and re-decompress each declared
/// `.traineddata`: ~4 MB for `eng`, ~10 MB for `osd`, tens of MB for a
/// multi-language set, on the UI isolate, per page of a scan loop.
///
/// The copy decision itself is re-checked on every call against the bytes held
/// here — no `exists()`/`existsSync()` — so a `.traineddata` deleted or damaged
/// mid-session is still repaired.
class _ResolvedTessData {
  const _ResolvedTessData(this.fileNames, this.assets);

  /// The declared file names, in config order.
  final List<String> fileNames;

  /// One entry per [fileNames]: the asset bytes read from the bundle.
  final List<Uint8List> assets;

  bool matches(List<String> other) => listEquals(fileNames, other);
}

_ResolvedTessData? _resolvedTessData;

/// Visible so a test can start from a clean isolate state.
@visibleForTesting
void debugResetTessDataCache() => _resolvedTessData = null;

Future<String?> loadTessDataToAppDocuments(
  String tessDataConfigAsset,
  String tessDataPathAsset,
) async {
  try {
    final Directory appDirectory = await getApplicationDocumentsDirectory();
    final Directory tessdataDirectory = Directory(
      join(appDirectory.path, 'tessdata'),
    );
    if (!await tessdataDirectory.exists()) {
      await tessdataDirectory.create(recursive: true);
    }
    final _ResolvedTessData resolved = await _resolveTessData(
      tessDataConfigAsset,
      tessDataPathAsset,
    );
    // The engine is about to read this directory: never hand it a tessdata set
    // that is missing a declared file or holds an empty one (issue #52).
    for (int i = 0; i < resolved.fileNames.length; i++) {
      final String fileName = resolved.fileNames[i];
      final File destFile = File(join(tessdataDirectory.path, fileName));
      final Uint8List? destinationBytes =
          await destFile.exists() ? await destFile.readAsBytes() : null;
      if (!TessDataAssets.needsCopy(
        assetBytes: resolved.assets[i],
        knownLength: null,
        destinationBytes: destinationBytes,
      )) {
        continue;
      }
      await destFile.writeAsBytes(resolved.assets[i], flush: true);
    }
    return appDirectory.path;
  } on MissingPlatformDirectoryException {
    // Headless Linux without XDG user dirs: skip the asset copy and let the
    // native plugin fall back to the system tessdata.
    return null;
  }
}

Future<_ResolvedTessData> _resolveTessData(
  String tessDataConfigAsset,
  String tessDataPathAsset,
) async {
  final String config = await _loadAssetString(tessDataConfigAsset);
  final List<String> fileNames = TessDataAssets.parseFileNames(
    config,
    configAsset: tessDataConfigAsset,
  );
  final _ResolvedTessData? cached = _resolvedTessData;
  if (cached != null && cached.matches(fileNames)) return cached;

  final List<Uint8List> assets = <Uint8List>[];
  for (final String fileName in fileNames) {
    assets.add(await _loadAssetBytes(join(tessDataPathAsset, fileName)));
  }
  return _resolvedTessData = _ResolvedTessData(
    List<String>.of(fileNames),
    List<Uint8List>.of(assets),
  );
}

Future<String> _loadAssetString(String assetPath) async {
  try {
    return await rootBundle.loadString(assetPath);
  } on Object catch (error) {
    throw TessDataAssets.unreadableAssetException(
      assetPath,
      cause: error,
      detail: 'is not carried by the asset bundle',
    );
  }
}

Future<Uint8List> _loadAssetBytes(String assetPath) async {
  final ByteData data;
  try {
    data = await rootBundle.load(assetPath);
  } on Object catch (error) {
    // Anything but a not-found has to read as itself: a decode failure, an
    // out-of-memory read and a bundle from the wrong build are not a missing
    // asset, and the first sentence of the message is what a crash report keeps.
    throw TessDataAssets.unreadableAssetException(
      assetPath,
      cause: error,
      detail: error is FlutterError &&
              error.diagnostics.any(
                (DiagnosticsNode node) =>
                    node.toStringDeep().contains('Unable to load'),
              )
          ? 'is not carried by the asset bundle'
          : 'could not be read from the asset bundle',
    );
  }
  final Uint8List bytes = Uint8List.sublistView(data);
  TessDataAssets.validateAssetBytes(assetPath, bytes.length);
  return bytes;
}
