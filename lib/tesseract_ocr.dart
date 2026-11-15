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

  /// Recognizes the text in the image at [imagePath] and returns the plain text.
  ///
  /// The tessdata set is copied from the asset bundle into the app's documents
  /// directory first unless [OCRConfig.tessDataPath] names one.
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

    return _recognize(method: method, imagePath: imagePath, config: config);
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

  /// The one recognition path every entry point shares.
  ///
  /// Exactly one of [imagePath] and [imageBytes] is given: the platform engines
  /// disagree about whether an image can be handed over in memory, so the
  /// channel carries whichever form this call has rather than a wrapper the
  /// natives would each have to unwrap. [method] is the channel method the
  /// result format selects (`extractText`, or `extractHocr` for the
  /// layout-aware output).
  static Future<String> _recognize({
    String method = 'extractText',
    String? imagePath,
    Uint8List? imageBytes,
    OCRConfig? config,
  }) async {
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
      if (imagePath != null) 'imagePath': imagePath,
      if (imageBytes != null) 'imageBytes': imageBytes,
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
  /// and is rejected. Detection classifies with the legacy templates carried by
  /// the `osd` model, so a call that names no language defaults to `osd` —
  /// bundle `osd.traineddata` for script-agnostic detection. Android and macOS
  /// answer `UNSUPPORTED_OSD` (see the README's platform matrix).
  ///
  /// [OCRConfig.options] travel with the call and are applied by the engines
  /// that accept Tesseract variables (iOS, Linux, Web); an explicit
  /// [OCRConfig.language] is honoured as given on every platform.
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

    // OSD classifies with the legacy templates of the `osd` model, so a call
    // that names no language runs on `osd` rather than the OCR default `eng`
    // (whose LSTM-only traineddata carries no legacy templates and would
    // answer TESSDATA_NOT_FOUND). An explicit language is honoured as given.
    final String language =
        (config == null || actualConfig.language.trim().isEmpty)
            ? 'osd'
            : actualConfig.language.trim();

    final Map<String, dynamic> args = {
      'imagePath': imagePath,
      'tessData': tessDataPath,
      'language': language,
      'engine': actualConfig.engine.toString().split('.').last,
      if (actualConfig.options != null) 'options': actualConfig.options,
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
