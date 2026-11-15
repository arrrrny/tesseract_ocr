import 'dart:typed_data';

import 'package:tesseract_ocr/ocr_engine_config.dart';

class TesseractWebOemConfig {
  final int oem;
  final bool useLegacy;

  const TesseractWebOemConfig({
    required this.oem,
    required this.useLegacy,
  });
}

class TesseractWebHelper {
  static const String defaultAssetLangPath = 'assets/assets/tessdata';

  static String resolveLangPath({
    required Uri baseUri,
    required String? overridePath,
  }) {
    final raw = overridePath?.trim();
    final String resolved;
    if (raw == null || raw.isEmpty) {
      resolved = baseUri.resolve(defaultAssetLangPath).toString();
    } else if (raw.startsWith('http://') || raw.startsWith('https://')) {
      resolved = raw;
    } else {
      resolved = baseUri.resolve(raw).toString();
    }
    return resolved.endsWith('/')
        ? resolved.substring(0, resolved.length - 1)
        : resolved;
  }

  static TesseractWebOemConfig resolveOem(Map<String, dynamic>? options) {
    final rawOem = options?[TesseractConfig.ocrEngineMode]?.toString().trim();
    final int oem = int.tryParse(rawOem ?? '') ?? 3; // OEM.DEFAULT
    // OEM 1 is LSTM_ONLY; all other modes (0, 2, 3) may require legacy core/data.
    final bool useLegacy = oem != 1;
    return TesseractWebOemConfig(oem: oem, useLegacy: useLegacy);
  }

  static bool resolveGzip(Map<String, dynamic>? options) {
    final raw = options?['gzip'];
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() == 'true';
    return false;
  }

  static Map<String, String> filterRuntimeOptions(
    Map<String, dynamic>? options,
  ) {
    if (options == null || options.isEmpty) {
      return const <String, String>{};
    }
    const reserved = <String>{
      'language',
      'engine',
      'tessDataPath',
      'gzip',
      TesseractConfig.ocrEngineMode,
    };
    final result = <String, String>{};
    for (final entry in options.entries) {
      if (reserved.contains(entry.key) || entry.value == null) {
        continue;
      }
      result[entry.key] = entry.value.toString();
    }
    return result;
  }

  /// The encoded image bytes a channel call carries, or null when it carries
  /// none.
  ///
  /// A `Uint8List` survives the standard codec as a byte array, but the
  /// platform implementations deliver it in whichever typed-data shape their own
  /// codec produced, so every one of those shapes is read here rather than
  /// trusted to be the same class.
  static Uint8List? resolveImageBytes(Object? raw) {
    if (raw is Uint8List) {
      return raw;
    }
    if (raw is ByteBuffer) {
      return raw.asUint8List();
    }
    if (raw is ByteData) {
      return raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    }
    return null;
  }

  static bool isDirectWebImageInput(String imagePath) {
    final trimmed = imagePath.trim().toLowerCase();
    return trimmed.startsWith('blob:') ||
        trimmed.startsWith('data:') ||
        trimmed.startsWith('http://') ||
        trimmed.startsWith('https://');
  }
}
