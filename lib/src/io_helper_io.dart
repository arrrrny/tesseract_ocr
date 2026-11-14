import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tesseract_ocr/src/tessdata_assets.dart';

Future<bool> fileExists(String path) => File(path).exists();

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

Future<String> loadTessDataToAppDocuments(
  String tessDataConfigAsset,
  String tessDataPathAsset,
) async {
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
    final Uint8List? destinationBytes = await destFile.exists()
        ? await destFile.readAsBytes()
        : null;
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
