import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/src/io_helper.dart' as io_helper;

class TesseractOcr {
  static const String TESS_DATA_CONFIG = 'assets/tessdata_config.json';

  // Adjusted path to potentially fix asset loading duplication on some platforms
  static const String TESS_DATA_PATH = 'assets/tessdata';

  static const MethodChannel _channel = MethodChannel('tesseract_ocr');

  @visibleForTesting
  static bool? debugIsWebOverride;

  static bool get _isWeb => debugIsWebOverride ?? kIsWeb;

  static Future<String> extractText(
    String imagePath, {
    OCRConfig? config,
  }) async {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError.value(imagePath, 'imagePath', 'Must not be empty');
    }

    final actualConfig = config ?? const OCRConfig();

    if (_isWeb) {
      if (actualConfig.engine == OCREngine.vision) {
        throw UnsupportedError(
          'OCREngine.vision is only supported on iOS. '
          'Use OCREngine.tesseract or OCREngine.defaultEngine on Web.',
        );
      }
    } else {
      if (!await io_helper.fileExists(imagePath)) {
        throw ArgumentError.value(
          imagePath,
          'imagePath',
          'Image file does not exist',
        );
      }
    }

    String? tessDataPath;
    if (actualConfig.engine != OCREngine.vision) {
      if (actualConfig.tessDataPath != null) {
        tessDataPath = actualConfig.tessDataPath;
      } else if (!_isWeb) {
        tessDataPath = await io_helper.loadTessDataToAppDocuments(
          TESS_DATA_CONFIG,
          TESS_DATA_PATH,
        );
      }
    }

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
}
