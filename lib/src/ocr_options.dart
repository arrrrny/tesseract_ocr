import 'package:tesseract_ocr/ocr_engine_config.dart';

/// The Tesseract options one recognition call carries, resolved per platform.
///
/// The Dart layer sends `OCRConfig.options` verbatim on the method channel, but
/// the platform engines disagree about what an option even means: Android's
/// `TessBaseAPI` takes the page segmentation mode through one call and every
/// other variable through another, while Vision has no PSM concept at all. Each
/// native plugin therefore needs the same three answers — which key is the PSM,
/// what integer it maps to, and which keys are left over — so the mapping lives
/// here once instead of being re-derived in Java, Swift and Kotlin.
class OcrOptionSpec {
  /// The values that `TessBaseAPI.PageSegMode` accepts.
  ///
  /// `TessBaseAPI.PageSegMode` covers 0–13; anything outside that range would
  /// be rejected by the enum lookup, so it is treated as absent.
  static const Set<int> androidPageSegModes = <int>{
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
  };

  /// Keys that never reach the OCR engine as a Tesseract variable.
  ///
  /// These are consumed by the Dart layer itself (`language`, `engine`,
  /// `tessDataPath`) or configure the recognition engine rather than a
  /// Tesseract variable (`tessedit_ocr_engine_mode` is applied through
  /// `setOem` on Android and `--oem` on the command-line platforms).
  static const Set<String> androidReservedKeys = <String>{
    'language',
    'engine',
    'tessDataPath',
    TesseractConfig.pageSegMode,
    TesseractConfig.ocrEngineMode,
  };

  /// The raw option map as it arrived from Dart, with non-string values
  /// stringified and null entries dropped.
  final Map<String, String> values;

  /// Keys whose value could not be used and must not be silently accepted.
  final List<String> ignoredKeys;

  const OcrOptionSpec._({required this.values, required this.ignoredKeys});

  /// Resolves [options] exactly as Android receives them.
  factory OcrOptionSpec.forAndroid(Map<String, dynamic>? options) {
    return OcrOptionSpec._resolve(
      options,
      reservedKeys: androidReservedKeys,
    );
  }

  /// Resolves [options] for the iOS Vision engine.
  ///
  /// Vision exposes no Tesseract variables, so the only options that survive
  /// are the ones with a Vision counterpart: [TesseractConfig.recognitionLevel]
  /// and [TesseractConfig.usesLanguageCorrection].
  factory OcrOptionSpec.forVision(Map<String, dynamic>? options) {
    final Map<String, String> values = <String, String>{};
    final List<String> ignoredKeys = <String>[];
    for (final entry in (options ?? const <String, dynamic>{}).entries) {
      if (entry.value == null) {
        ignoredKeys.add(entry.key);
        continue;
      }
      if (entry.key == TesseractConfig.recognitionLevel) {
        values[entry.key] = entry.value.toString();
        continue;
      }
      if (entry.key == TesseractConfig.usesLanguageCorrection) {
        final bool? parsed = parseBool(entry.value);
        if (parsed == null) {
          ignoredKeys.add(entry.key);
          continue;
        }
        values[entry.key] = parsed ? 'true' : 'false';
        continue;
      }
      ignoredKeys.add(entry.key);
    }
    return OcrOptionSpec._(values: values, ignoredKeys: ignoredKeys);
  }

  factory OcrOptionSpec._resolve(
    Map<String, dynamic>? options, {
    required Set<String> reservedKeys,
  }) {
    final Map<String, String> values = <String, String>{};
    final List<String> ignoredKeys = <String>[];
    for (final entry in (options ?? const <String, dynamic>{}).entries) {
      if (entry.value == null) {
        ignoredKeys.add(entry.key);
        continue;
      }
      if (entry.key == TesseractConfig.pageSegMode) {
        // The PSM travels as a value here so the plugin can read the requested
        // mode back, but it is applied through setPageSegMode rather than as a
        // Tesseract variable, so `variables` excludes it again below.
        if (pageSegModeFor(entry.value) == null) {
          ignoredKeys.add(entry.key);
        }
        values[entry.key] = entry.value.toString();
        continue;
      }
      if (reservedKeys.contains(entry.key)) {
        continue;
      }
      values[entry.key] = entry.value.toString();
    }
    return OcrOptionSpec._(values: values, ignoredKeys: ignoredKeys);
  }

  /// Every option except the page segmentation mode, which Android applies
  /// through its own call rather than as a Tesseract variable.
  Map<String, String> get variables {
    final Map<String, String> result = <String, String>{};
    for (final entry in values.entries) {
      if (entry.key == TesseractConfig.pageSegMode) {
        continue;
      }
      result[entry.key] = entry.value;
    }
    return result;
  }

  /// The page segmentation mode as it was sent, for a plugin's own log line.
  String? get rawPageSegMode => values[TesseractConfig.pageSegMode];

  /// Whether the caller asked for a mode Android cannot apply.
  bool get hasIgnoredOptions => ignoredKeys.isNotEmpty;

  /// The PSM an integer or numeric string maps to, or null when it is not one.
  static int? pageSegModeFor(Object? value) {
    final int? mode = value is int ? value : int.tryParse('$value'.trim());
    if (mode == null || !androidPageSegModes.contains(mode)) {
      return null;
    }
    return mode;
  }

  /// The `VNRecognizeTextRequest.recognitionLevel` to use.
  ///
  /// Vision has exactly two levels, `fast` and `accurate`; anything else keeps
  /// the historical `.accurate` default.
  static VisionRecognitionLevel visionRecognitionLevel(
    Map<String, dynamic>? options,
  ) {
    final String? raw = options?[TesseractConfig.recognitionLevel];
    final String normalized = (raw ?? '').trim().toLowerCase();
    return normalized == 'fast'
        ? VisionRecognitionLevel.fast
        : VisionRecognitionLevel.accurate;
  }

  /// The `usesLanguageCorrection` flag, defaulting to Vision's own default.
  static bool visionUsesLanguageCorrection(Map<String, dynamic>? options) {
    final Object? raw = options?[TesseractConfig.usesLanguageCorrection];
    if (raw == null) {
      return true;
    }
    return parseBool(raw) ?? true;
  }

  /// Parses the boolean spellings a Dart caller may send across the channel.
  static bool? parseBool(Object? value) {
    if (value is bool) {
      return value;
    }
    final String normalized = '$value'.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return null;
  }
}

/// The two recognition levels Vision exposes.
enum VisionRecognitionLevel {
  /// `VNRequestTextRecognitionLevel.fast`
  fast,

  /// `VNRequestTextRecognitionLevel.accurate`
  accurate,
}
