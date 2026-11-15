import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:tesseract_ocr/src/web_helper.dart';

class TesseractOcrWeb {
  static const String tesseractJsVersion = '6.0.1';
  static const String tesseractJsCdnUrl =
      'https://cdn.jsdelivr.net/npm/tesseract.js@$tesseractJsVersion/dist/tesseract.min.js';

  static Completer<void>? _scriptLoadCompleter;

  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'tesseract_ocr',
      const StandardMethodCodec(),
      registrar,
    );
    final instance = TesseractOcrWeb();
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'getPlatformVersion':
        final navigator = globalContext['navigator'] as JSObject?;
        final userAgent = navigator?['userAgent'] as JSString?;
        final ua = userAgent?.toDart ?? '';
        return ua.isEmpty ? 'Web' : 'Web ($ua)';
      case 'extractText':
      case 'extractHocr':
        return _extract(
          call.arguments,
          isHocr: call.method == 'extractHocr',
        );
      case 'detectOrientationScript':
        return _detectOrientationScript(call.arguments);
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: "tesseract_ocr for web doesn't implement '${call.method}'",
        );
    }
  }

  Future<String> _extract(
    dynamic arguments, {
    required bool isHocr,
  }) async {
    if (arguments is! Map) {
      throw PlatformException(
        code: 'INVALID_ARGUMENTS',
        message: 'Arguments were invalid or could not be parsed.',
      );
    }

    final params = Map<String, dynamic>.from(arguments);
    final engine = params['engine']?.toString().toLowerCase();
    if (engine == 'vision') {
      throw PlatformException(
        code: 'UNSUPPORTED_ENGINE',
        message:
            'Apple Vision engine is only supported on iOS. Use OCREngine.tesseract or OCREngine.defaultEngine on Web.',
      );
    }

    final rawImagePath = params['imagePath']?.toString().trim() ?? '';
    if (rawImagePath.isEmpty) {
      throw PlatformException(
        code: 'MISSING_PARAMS',
        message: "Required parameter 'imagePath' is missing.",
      );
    }

    final rawLanguage = params['language']?.toString().trim() ?? '';
    final language = rawLanguage.isEmpty ? 'eng' : rawLanguage;

    final rawOptions = params['options'];
    final options =
        rawOptions is Map ? Map<String, dynamic>.from(rawOptions) : null;

    final rawTessData = params['tessData']?.toString().trim();
    if (rawTessData == null || rawTessData.isEmpty) {
      await _verifyBundledTrainedData(language);
    }

    final langPath = TesseractWebHelper.resolveLangPath(
      baseUri: Uri.base,
      overridePath: rawTessData,
    );
    final oemConfig = TesseractWebHelper.resolveOem(options);
    final gzip = TesseractWebHelper.resolveGzip(options);
    final runtimeOptions = TesseractWebHelper.filterRuntimeOptions(options);

    final JSAny imageInput = await _resolveImageInput(rawImagePath);

    await _ensureTesseractLoaded();

    final tesseractObj = globalContext['Tesseract'] as JSObject?;
    if (tesseractObj == null) {
      throw PlatformException(
        code: 'TESSERACT_JS_NOT_AVAILABLE',
        message: 'window.Tesseract is not available after script load.',
      );
    }

    final workerOptions = <String, Object?>{
      'langPath': langPath,
      'gzip': gzip,
      'legacyCore': oemConfig.useLegacy,
      'legacyLang': oemConfig.useLegacy,
    }.jsify()!;

    JSObject? worker;
    try {
      final workerPromise = tesseractObj.callMethodVarArgs<JSPromise<JSObject>>(
        'createWorker'.toJS,
        <JSAny?>[
          language.toJS,
          oemConfig.oem.toJS,
          workerOptions,
        ],
      );
      worker = await workerPromise.toDart;

      if (runtimeOptions.isNotEmpty) {
        final setParamsPromise = worker.callMethodVarArgs<JSPromise<JSAny?>>(
          'setParameters'.toJS,
          <JSAny?>[runtimeOptions.jsify()!],
        );
        await setParamsPromise.toDart;
      }

      final outputOptions = <String, Object?>{
        'text': !isHocr,
        'hocr': isHocr,
      }.jsify()!;

      final recognizePromise = worker.callMethodVarArgs<JSPromise<JSObject>>(
        'recognize'.toJS,
        <JSAny?>[
          imageInput,
          <String, Object?>{}.jsify()!,
          outputOptions,
        ],
      );
      final resultObj = await recognizePromise.toDart;
      final dataObj = resultObj['data'] as JSObject?;
      final rawField =
          dataObj == null ? null : (isHocr ? dataObj['hocr'] : dataObj['text']);
      final extracted = rawField as JSString?;
      return extracted?.toDart ?? '';
    } catch (error) {
      if (error is PlatformException) rethrow;
      throw PlatformException(
        code: 'OCR_PROCESS_ERROR',
        message: 'Tesseract.js OCR failed: $error',
      );
    } finally {
      if (worker != null) {
        try {
          await worker.callMethod<JSPromise<JSAny?>>('terminate'.toJS).toDart;
        } catch (_) {
          // Ignore worker cleanup errors.
        }
      }
    }
  }

  /// Detects orientation & script through tesseract.js's `worker.detect()`.
  ///
  /// `detect()` returns `{ data: { script, script_confidence,
  /// orientation_degrees, orientation_confidence, ... } }`; this maps that onto
  /// the same four keys the native engines answer with.
  Future<Map<String, dynamic>> _detectOrientationScript(
    dynamic arguments,
  ) async {
    if (arguments is! Map) {
      throw PlatformException(
        code: 'INVALID_ARGUMENTS',
        message: 'Arguments were invalid or could not be parsed.',
      );
    }

    final params = Map<String, dynamic>.from(arguments);
    final engine = params['engine']?.toString().toLowerCase();
    if (engine == 'vision') {
      throw PlatformException(
        code: 'UNSUPPORTED_ENGINE',
        message:
            'Apple Vision engine does not support OSD. Use OCREngine.tesseract or OCREngine.defaultEngine on Web.',
      );
    }

    final rawImagePath = params['imagePath']?.toString().trim() ?? '';
    if (rawImagePath.isEmpty) {
      throw PlatformException(
        code: 'MISSING_PARAMS',
        message: "Required parameter 'imagePath' is missing.",
      );
    }

    // Orientation & script detection runs on the OSD model; fall back to it
    // when the caller did not name a language, mirroring the native engines.
    final rawLanguage = params['language']?.toString().trim() ?? '';
    final language = rawLanguage.isEmpty ? 'osd' : rawLanguage;

    final rawTessData = params['tessData']?.toString().trim();
    if (rawTessData == null || rawTessData.isEmpty) {
      await _verifyBundledTrainedData(language);
    }

    final langPath = TesseractWebHelper.resolveLangPath(
      baseUri: Uri.base,
      overridePath: rawTessData,
    );

    final JSAny imageInput = await _resolveImageInput(rawImagePath);

    await _ensureTesseractLoaded();

    final tesseractObj = globalContext['Tesseract'] as JSObject?;
    if (tesseractObj == null) {
      throw PlatformException(
        code: 'TESSERACT_JS_NOT_AVAILABLE',
        message: 'window.Tesseract is not available after script load.',
      );
    }

    // OSD classifies with the legacy engine's templates, so the worker is
    // created with the legacy core/lang enabled regardless of the OCR OEM.
    final workerOptions = <String, Object?>{
      'langPath': langPath,
      'gzip': false,
      'legacyCore': true,
      'legacyLang': true,
    }.jsify()!;

    JSObject? worker;
    try {
      final workerPromise = tesseractObj.callMethodVarArgs<JSPromise<JSObject>>(
        'createWorker'.toJS,
        <JSAny?>[
          language.toJS,
          1.toJS,
          workerOptions,
        ],
      );
      worker = await workerPromise.toDart;

      final detectPromise = worker.callMethodVarArgs<JSPromise<JSObject>>(
        'detect'.toJS,
        <JSAny?>[imageInput],
      );
      final resultObj = await detectPromise.toDart;
      final dataObj = resultObj['data'] as JSObject?;

      return <String, dynamic>{
        'orientation':
            (dataObj?['orientation_degrees'] as JSNumber?)?.toDartInt ?? 0,
        'orientation_conf':
            (dataObj?['orientation_confidence'] as JSNumber?)?.toDartDouble ??
                0.0,
        'script': (dataObj?['script'] as JSString?)?.toDart ?? '',
        'script_conf':
            (dataObj?['script_confidence'] as JSNumber?)?.toDartDouble ?? 0.0,
      };
    } catch (error) {
      if (error is PlatformException) rethrow;
      throw PlatformException(
        code: 'OCR_PROCESS_ERROR',
        message: 'tesseract.js OSD detection failed: $error',
      );
    } finally {
      if (worker != null) {
        try {
          await worker.callMethod<JSPromise<JSAny?>>('terminate'.toJS).toDart;
        } catch (_) {
          // Ignore worker cleanup errors.
        }
      }
    }
  }

  Future<void> _verifyBundledTrainedData(String language) async {
    final languageParts = language
        .split('+')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (languageParts.isEmpty) return;

    try {
      final configRaw =
          await rootBundle.loadString('assets/tessdata_config.json');
      final configJson = jsonDecode(configRaw) as Map<String, dynamic>;
      final files = (configJson['files'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toSet();
      final missing = languageParts
          .where((part) => !files.contains('$part.traineddata'))
          .map((part) => '$part.traineddata')
          .toList();
      if (missing.isNotEmpty) {
        throw PlatformException(
          code: 'TESSDATA_NOT_FOUND',
          message:
              'Missing traineddata file(s) ${missing.join(', ')} in assets/tessdata_config.json. Bundle them in assets/tessdata/ and declare them in tessdata_config.json.',
        );
      }
    } catch (error) {
      if (error is PlatformException) rethrow;
      throw PlatformException(
        code: 'TESSDATA_NOT_FOUND',
        message:
            'Could not load assets/tessdata_config.json ($error). Ensure tessdata assets are declared in pubspec.yaml or pass OCRConfig(tessDataPath: ...).',
      );
    }
  }

  Future<JSAny> _resolveImageInput(String imagePath) async {
    if (TesseractWebHelper.isDirectWebImageInput(imagePath)) {
      return imagePath.toJS;
    }

    try {
      final ByteData data = await rootBundle.load(imagePath);
      final Uint8List bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return bytes.toJS;
    } catch (_) {
      return Uri.base.resolve(imagePath).toString().toJS;
    }
  }

  Future<void> _ensureTesseractLoaded() async {
    final existing = globalContext['Tesseract'];
    if (existing != null && !existing.isUndefinedOrNull) {
      return;
    }

    if (_scriptLoadCompleter != null) {
      return _scriptLoadCompleter!.future;
    }

    final completer = Completer<void>();
    _scriptLoadCompleter = completer;

    final doc = globalContext['document'] as JSObject;
    final script = doc.callMethod<JSObject>(
      'createElement'.toJS,
      'script'.toJS,
    );
    script.setProperty('src'.toJS, tesseractJsCdnUrl.toJS);
    script.setProperty('async'.toJS, true.toJS);
    script.setProperty(
      'onload'.toJS,
      ((JSAny? _) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }).toJS,
    );
    script.setProperty(
      'onerror'.toJS,
      ((JSAny? _) {
        _scriptLoadCompleter = null;
        if (!completer.isCompleted) {
          completer.completeError(
            PlatformException(
              code: 'TESSERACT_JS_LOAD_FAILED',
              message:
                  'Failed to load tesseract.js from $tesseractJsCdnUrl. For offline or strict CSP environments, include tesseract.min.js via a <script> tag in web/index.html.',
            ),
          );
        }
      }).toJS,
    );

    final target = (doc['head'] ?? doc['documentElement']) as JSObject;
    target.callMethod<JSAny?>('appendChild'.toJS, script);

    return completer.future;
  }
}
