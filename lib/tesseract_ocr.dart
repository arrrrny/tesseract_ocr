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

  /// Recognizes the text in the image at [imagePath].
  ///
  /// The tessdata set is copied from the asset bundle into the app's documents
  /// directory first unless [OCRConfig.tessDataPath] names one.
  static Future<String> extractText(
    String imagePath, {
    OCRConfig? config,
  }) async {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError.value(imagePath, 'imagePath', 'Must not be empty');
    }

    return _recognize(imagePath: imagePath, config: config);
  }

  /// Recognizes the text in an encoded image held in memory.
  ///
  /// A camera-first caller already has the bytes, and making it write a
  /// temporary file first is work the plugin can do itself: the bytes travel to
  /// the platform engine as they are, and each engine takes them through its own
  /// native entry point (a bitmap on Android, a typed array on Web, a data
  /// buffer on Apple platforms). Only the two engines that are driven by a
  /// command line — macOS and Linux — materialise the bytes into a temporary
  /// file, which they delete again.
  ///
  /// [bytes] must be a complete encoded image (PNG, JPEG, …), exactly the file
  /// content an image path would have pointed at.
  static Future<String> extractTextFromBytes(
    Uint8List bytes, {
    OCRConfig? config,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'Must not be empty');
    }

    return _recognize(imageBytes: bytes, config: config);
  }

  /// The one recognition path both entry points share.
  ///
  /// Exactly one of [imagePath] and [imageBytes] is given: the platform engines
  /// disagree about whether an image can be handed over in memory, so the
  /// channel carries whichever form this call has rather than a wrapper the
  /// natives would each have to unwrap.
  static Future<String> _recognize({
    String? imagePath,
    Uint8List? imageBytes,
    OCRConfig? config,
  }) async {
    final actualConfig = config ?? const OCRConfig();

    if (_isWeb) {
      if (actualConfig.engine == OCREngine.vision) {
        throw UnsupportedError(
          'OCREngine.vision is only supported on iOS. '
          'Use OCREngine.tesseract or OCREngine.defaultEngine on Web.',
        );
      }
    } else {
      final String? path = imagePath;
      if (path != null && !await io_helper.fileExists(path)) {
        throw ArgumentError.value(
            path, 'imagePath', 'Image file does not exist');
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
      if (imagePath != null) 'imagePath': imagePath,
      if (imageBytes != null) 'imageBytes': imageBytes,
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
