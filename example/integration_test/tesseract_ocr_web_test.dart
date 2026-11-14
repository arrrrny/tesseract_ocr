import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'extractText recognizes meaningful text using Web Tesseract.js',
    (_) async {
      expect(
        kIsWeb,
        isTrue,
        reason: 'This fixture validates the Web plugin.',
      );

      const assetPath = 'packages/tesseract_ocr/images/testocr.png';
      final imageData = await rootBundle.load(assetPath);
      final bytes = imageData.buffer.asUint8List(
        imageData.offsetInBytes,
        imageData.lengthInBytes,
      );
      final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';

      final defaultRawText = await TesseractOcr.extractText(dataUrl);
      final defaultNormalized =
          defaultRawText.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
      expect(
        defaultNormalized,
        contains('this is a lot of 12 point text to test the ocr code'),
        reason: 'Default Web OCR output: ${jsonEncode(defaultRawText)}',
      );

      final rawText = await TesseractOcr.extractText(
        assetPath,
        config: const OCRConfig(
          language: 'eng',
          engine: OCREngine.tesseract,
        ),
      );
      final normalizedText =
          rawText.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
      final reason = 'Raw Web OCR output: ${jsonEncode(rawText)}';

      expect(
        normalizedText,
        contains('this is a lot of 12 point text to test the ocr code'),
        reason: reason,
      );
      expect(
        normalizedText,
        contains('the quick brown dog jumped over the lazy fox'),
        reason: reason,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'extractText supports bundled legacy and LSTM traineddata on Web',
    (_) async {
      expect(kIsWeb, isTrue);

      const assetPath = 'packages/tesseract_ocr/images/testocr.png';
      final ocrbText = await TesseractOcr.extractText(
        assetPath,
        config: const OCRConfig(
          language: 'OCRB',
          engine: OCREngine.tesseract,
        ),
      );
      expect(ocrbText, isA<String>());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'extractText rejects Apple Vision engine on Web',
    (_) async {
      expect(kIsWeb, isTrue);

      await expectLater(
        () => TesseractOcr.extractText(
          'packages/tesseract_ocr/images/testocr.png',
          config: const OCRConfig(engine: OCREngine.vision),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );
}
