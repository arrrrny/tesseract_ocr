import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

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
  await _copyTessDataToAppDocumentsDirectory(
    tessdataDirectory,
    tessDataConfigAsset,
    tessDataPathAsset,
  );
  return appDirectory.path;
}

Future<void> _copyTessDataToAppDocumentsDirectory(
  String tessdataDirectory,
  String tessDataConfigAsset,
  String tessDataPathAsset,
) async {
  final String config = await rootBundle.loadString(tessDataConfigAsset);
  final Map<String, dynamic> files = jsonDecode(config) as Map<String, dynamic>;
  for (final file in files['files'] as List<dynamic>) {
    final fileName = file.toString();
    if (fileName.contains('..') || fileName.startsWith('/')) {
      throw ArgumentError('Invalid file name in tessdata_config.json: $fileName');
    }
    final assetPath = join(tessDataPathAsset, fileName);
    final destFile = File(join(tessdataDirectory, fileName));
    if (!await destFile.exists()) {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await destFile.writeAsBytes(bytes);
    }
  }
}
