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

  /// Runs OCR on [imagePath] and returns the recognized plain text.
  ///
  /// See [extractHocr] for the layout-aware (bounding-box) output format.
  static Future<String> extractText(
    String imagePath, {
    OCRConfig? config,
  }) {
    return _extract('extractText', imagePath, config: config);
  }

  /// Runs OCR on [imagePath] and returns the result as hOCR.
  ///
  /// hOCR is an HTML-like, layout-aware representation of the recognized text:
  /// every line, word and symbol carries its bounding box, so callers doing
  /// layout-aware extraction (word/line structure, positions) have a supported
  /// path instead of parsing plain text.
  ///
  /// It is produced by the Tesseract engine, which backs Android, Web, macOS,
  /// iOS and Linux. Apple's Vision engine ([OCREngine.vision]) has no hOCR
  /// output, so requesting hOCR with it throws [UnsupportedError].
  static Future<String> extractHocr(
    String imagePath, {
    OCRConfig? config,
  }) {
    return _extract('extractHocr', imagePath, config: config);
  }

  static Future<String> _extract(
    String method,
    String imagePath, {
    OCRConfig? config,
  }) async {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError.value(imagePath, 'imagePath', 'Must not be empty');
    }

    final actualConfig = config ?? const OCRConfig();

    if (method == 'extractHocr' && actualConfig.engine == OCREngine.vision) {
      throw UnsupportedError(
        'hOCR output is only available with OCREngine.tesseract or '
        'OCREngine.defaultEngine; OCREngine.vision does not produce hOCR.',
      );
    }

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

    final String? extracted = await _channel.invokeMethod<String>(
      method,
      args,
    );
    return extracted ?? '';
  }
}
