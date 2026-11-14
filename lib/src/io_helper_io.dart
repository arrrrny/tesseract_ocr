import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tesseract_ocr/src/tessdata_assets.dart';

Future<bool> fileExists(String path) => File(path).exists();

Future<String> loadTessDataToAppDocuments(
  String tessDataConfigAsset,
  String tessDataPathAsset,
) async {
  final Directory appDirectory = await getApplicationDocumentsDirectory();
  final String tessdataDirectory = join(appDirectory.path, 'tessdata');
  if (!await Directory(tessdataDirectory).exists()) {
    await Directory(tessdataDirectory).create(recursive: true);
  }
  final List<String> fileNames = await _copyTessDataToAppDocumentsDirectory(
    tessdataDirectory,
    tessDataConfigAsset,
    tessDataPathAsset,
  );
  // The engine is about to read this directory: never hand it a tessdata set
  // that is missing a declared file or holds an empty one (issue #52).
  for (final String fileName in fileNames) {
    TessDataAssets.validateTessDataFile(
      File(join(tessdataDirectory, fileName)),
      join(tessDataPathAsset, fileName),
    );
  }
  return appDirectory.path;
}

Future<List<String>> _copyTessDataToAppDocumentsDirectory(
  String tessdataDirectory,
  String tessDataConfigAsset,
  String tessDataPathAsset,
) async {
  final String config = await _loadAssetString(tessDataConfigAsset);
  final List<String> fileNames = TessDataAssets.parseFileNames(
    config,
    configAsset: tessDataConfigAsset,
  );
  for (final String fileName in fileNames) {
    final String assetPath = join(tessDataPathAsset, fileName);
    final Uint8List bytes = await _loadAssetBytes(assetPath);
    final File destFile = File(join(tessdataDirectory, fileName));
    final int? existingLength =
        await destFile.exists() ? await destFile.length() : null;
    if (TessDataAssets.needsCopy(
      existingLength: existingLength,
      assetLength: bytes.length,
    )) {
      await destFile.writeAsBytes(bytes);
    }
  }
  return fileNames;
}

Future<String> _loadAssetString(String assetPath) async {
  try {
    return await rootBundle.loadString(assetPath);
  } on Object catch (error) {
    throw TessDataAssets.missingAssetException(assetPath, cause: error);
  }
}

Future<Uint8List> _loadAssetBytes(String assetPath) async {
  final ByteData data;
  try {
    data = await rootBundle.load(assetPath);
  } on Object catch (error) {
    throw TessDataAssets.missingAssetException(assetPath, cause: error);
  }
  final Uint8List bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  TessDataAssets.validateAssetBytes(assetPath, bytes.length);
  return bytes;
}
