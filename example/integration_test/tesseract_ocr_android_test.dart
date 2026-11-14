import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'extractText recognizes meaningful text using native Android Tesseract',
    (_) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'This fixture validates the Android plugin.',
      );

      const fileName = 'testocr.png';
      final imageData = await rootBundle.load(
        'packages/tesseract_ocr/images/$fileName',
      );
      final fixtureDirectory = await Directory.systemTemp.createTemp(
        'tesseract_ocr_integration_',
      );

      addTearDown(() async {
        if (await fixtureDirectory.exists()) {
          await fixtureDirectory.delete(recursive: true);
        }
      });

      final imageFile = File(
        '${fixtureDirectory.path}${Platform.pathSeparator}$fileName',
      );
      await imageFile.writeAsBytes(
        imageData.buffer.asUint8List(
          imageData.offsetInBytes,
          imageData.lengthInBytes,
        ),
        flush: true,
      );

      final rawText = await TesseractOcr.extractText(
        imageFile.path,
        config: const OCRConfig(
          language: 'eng',
          engine: OCREngine.tesseract,
        ),
      );
      final normalizedText =
          rawText.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
      final reason = 'Raw OCR output: ${jsonEncode(rawText)}';

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
}
