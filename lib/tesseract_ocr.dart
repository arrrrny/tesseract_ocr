import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/osd_result.dart';
import 'package:tesseract_ocr/src/io_helper.dart' as io_helper;

export 'osd_result.dart';

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

  /// Detects the orientation and script of [imagePath] with Tesseract's OSD
  /// (orientation & script detection).
  ///
  /// Mirrors `pytesseract.image_to_osd`: the returned [OsdResult] carries the
  /// page rotation in [OsdResult.orientationDegrees] (rotate the image by that
  /// many degrees to make it upright), the detected writing script in
  /// [OsdResult.scriptName], and a confidence for each. Use it to auto-rotate or
  /// decline an image before running [extractText].
  ///
  /// OSD is a Tesseract engine capability; [OCREngine.vision] has no equivalent
  /// and is rejected. The engine needs a language model that carries the legacy
  /// templates the detector classifies with — pass `OCRConfig(language: 'osd')`
  /// and bundle `osd.traineddata` for script-agnostic detection.
  static Future<OsdResult> detectOrientationAndScript(
    String imagePath, {
    OCRConfig? config,
  }) async {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError.value(imagePath, 'imagePath', 'Must not be empty');
    }

    final actualConfig = config ?? const OCRConfig();

    if (actualConfig.engine == OCREngine.vision) {
      throw UnsupportedError(
        'OSD is only available with the Tesseract engine. '
        'OCREngine.vision does not expose orientation & script detection.',
      );
    }

    if (!_isWeb) {
      if (!await io_helper.fileExists(imagePath)) {
        throw ArgumentError.value(
          imagePath,
          'imagePath',
          'Image file does not exist',
        );
      }
    }

    String? tessDataPath;
    if (actualConfig.tessDataPath != null) {
      tessDataPath = actualConfig.tessDataPath;
    } else if (!_isWeb) {
      tessDataPath = await io_helper.loadTessDataToAppDocuments(
        TESS_DATA_CONFIG,
        TESS_DATA_PATH,
      );
    }

    final Map<String, dynamic> args = {
      'imagePath': imagePath,
      'tessData': tessDataPath,
      'language': actualConfig.language,
      'engine': actualConfig.engine.toString().split('.').last,
    };

    final Map<String, dynamic>? result =
        await _channel.invokeMapMethod<String, dynamic>(
      'detectOrientationScript',
      args,
    );

    if (result == null) {
      throw PlatformException(
        code: 'OSD_NO_RESULT',
        message: 'Orientation & script detection returned no result.',
      );
    }

    return OsdResult.fromMap(result);
  }
}
