import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart'; // Import OCRConfig

class TesseractOcr {
  static const String TESS_DATA_CONFIG = 'assets/tessdata_config.json';
  static const String TESS_DATA_PATH = 'assets/tessdata';
  static const MethodChannel _channel = const MethodChannel('tesseract_ocr');

  static Future<String> extractText(
    String imagePath, {
    OCRConfig? config, // Add optional OCRConfig parameter
  }) async {
    assert(await File(imagePath).exists(), true);

    // Use config if provided, otherwise create a default config
    final actualConfig = config ?? const OCRConfig();

    // If using Tesseract engine, ensure tessData is loaded
    String? tessDataPath;
    if (actualConfig.engine != OCREngine.vision) {
      // Check if NOT Vision
      tessDataPath = await _loadTessData();
    }

    // Build the arguments map
    final Map<String, dynamic> args = {
      'imagePath': imagePath,
      'tessDataPath': tessDataPath, // Pass the loaded path
      'config': actualConfig.toMap(), // Pass the config as a map
    };

    final String extractedText =
        await _channel.invokeMethod('extractText', args);

    return extractedText;
  }

  static Future<String> _loadTessData() async {
    final Directory appDirectory = await getApplicationDocumentsDirectory();
    final String tessdataDirectory = join(appDirectory.path, 'tessdata');

    if (!await Directory(tessdataDirectory).exists()) {
      await Directory(tessdataDirectory).create();
    }
    await _copyTessDataToAppDocumentsDirectory(tessdataDirectory);
    return appDirectory.path;
  }

  static Future _copyTessDataToAppDocumentsDirectory(
      String tessdataDirectory) async {
    final String config = await rootBundle.loadString(TESS_DATA_CONFIG);
    Map<String, dynamic> files = jsonDecode(config);
    for (var file in files["files"]) {
      if (!await File('$tessdataDirectory/$file').exists()) {
        final ByteData data = await rootBundle.load('$TESS_DATA_PATH/$file');
        final Uint8List bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        await File('$tessdataDirectory/$file').writeAsBytes(bytes);
      }
    }
  }
}
