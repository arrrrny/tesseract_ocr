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

  @visibleForTesting
  static bool? debugIsMacOSOverride;

  static bool get _isMacOS =>
      debugIsMacOSOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS);

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
      if (_isMacOS && actualConfig.engine == OCREngine.vision) {
        throw UnsupportedError(
          'OCREngine.vision is only supported on iOS. '
          'Use OCREngine.tesseract or OCREngine.defaultEngine on macOS.',
        );
      }
    }

    String? tessDataPath;
    if (actualConfig.engine != OCREngine.vision) {
      final String configured = actualConfig.tessDataPath?.trim() ?? '';
      if (configured.isNotEmpty) {
        // A tessdata directory already on the device — downloaded at runtime or
        // shared with another app — replaces the asset copy entirely (issue
        // #56): the engine is pointed at where the files actually are, and a
        // directory without them is refused here instead of inside the engine.
        // On Web there is no filesystem to check: the override is the `langPath`
        // the Tesseract.js worker fetches from, so it travels untouched.
        tessDataPath = _isWeb
            ? configured
            : await io_helper.resolveTessDataDirectory(
                configured,
                language: actualConfig.language,
              );
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
