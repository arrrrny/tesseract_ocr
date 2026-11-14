import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';

class TesseractOcr {
  static const String TESS_DATA_CONFIG = 'assets/tessdata_config.json';

  // Adjusted path to potentially fix asset loading duplication on some platforms
  static const String TESS_DATA_PATH = 'assets/tessdata';

  static const MethodChannel _channel = MethodChannel('tesseract_ocr');

  @visibleForTesting
  static bool? debugIsMacOSOverride;

  static bool get _isMacOS => debugIsMacOSOverride ?? Platform.isMacOS;

  static Future<String> extractText(
    String imagePath, {
    OCRConfig? config,
  }) async {
    if (!await File(imagePath).exists()) {
      throw FileSystemException('Image file does not exist', imagePath);
    }

    // Use config if provided, otherwise create a default config
    final actualConfig = config ?? const OCRConfig();

    if (_isMacOS && actualConfig.engine == OCREngine.vision) {
      throw UnsupportedError(
        'OCREngine.vision is only supported on iOS. '
        'Use OCREngine.tesseract or OCREngine.defaultEngine on macOS.',
      );
    }

    // If using Tesseract engine, ensure tessData is loaded
    String? tessDataPath;
    if (actualConfig.engine != OCREngine.vision) {
      tessDataPath = actualConfig.tessDataPath ?? await _loadTessData();
    }

    // Build the arguments map
    final Map<String, dynamic> args = {
      'imagePath': imagePath,
      'tessData': tessDataPath,
      'language': actualConfig.language,
      'engine': actualConfig.engine.toString().split('.').last,
      if (actualConfig.options != null) 'options': actualConfig.options,
    };

    final String? extractedText = await _channel.invokeMethod<String>(
      'extractText',
      args,
    );
    return extractedText ?? '';
  }

  static Future<String> _loadTessData() async {
    final Directory appDirectory = await getApplicationDocumentsDirectory();
    final String tessdataDirectory = join(appDirectory.path, 'tessdata');
    if (!await Directory(tessdataDirectory).exists()) {
      await Directory(tessdataDirectory).create(recursive: true);
    }
    await _copyTessDataToAppDocumentsDirectory(tessdataDirectory);
    return appDirectory.path;
  }

  static Future<void> _copyTessDataToAppDocumentsDirectory(
    String tessdataDirectory,
  ) async {
    final String config = await rootBundle.loadString(TESS_DATA_CONFIG);
    final Map<String, dynamic> files =
        jsonDecode(config) as Map<String, dynamic>;
    for (final file in files['files'] as List<dynamic>) {
      final fileName = file.toString();
      final assetPath = join(TESS_DATA_PATH, fileName);
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
}
