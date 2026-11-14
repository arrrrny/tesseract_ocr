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
    'extractText recognizes meaningful text using macOS Tesseract',
    (_) async {
      expect(
        Platform.isMacOS,
        isTrue,
        reason: 'This fixture validates the macOS plugin.',
      );

      const fileName = 'testocr.png';
      final imageData = await rootBundle.load(
        'packages/tesseract_ocr/images/$fileName',
      );
      final fixtureDirectory = await Directory.systemTemp.createTemp(
        'tesseract_ocr_macos_integration_',
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

      final defaultRawText = await TesseractOcr.extractText(imageFile.path);
      final defaultNormalizedText =
          defaultRawText.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
      expect(
        defaultNormalizedText,
        contains('this is a lot of 12 point text to test the ocr code'),
        reason: 'Default OCR output: ${jsonEncode(defaultRawText)}',
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

  testWidgets(
    'extractText supports bundled traineddata language selection on macOS',
    (_) async {
      expect(Platform.isMacOS, isTrue);

      const fileName = 'testocr.png';
      final imageData = await rootBundle.load(
        'packages/tesseract_ocr/images/$fileName',
      );
      final fixtureDirectory = await Directory.systemTemp.createTemp(
        'tesseract_ocr_macos_lang_',
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

      final ocrbText = await TesseractOcr.extractText(
        imageFile.path,
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
    'extractText reports clear errors for unusable inputs on macOS',
    (_) async {
      expect(Platform.isMacOS, isTrue);

      final fixtureDirectory = await Directory.systemTemp.createTemp(
        'tesseract_ocr_macos_error_',
      );
      addTearDown(() async {
        if (await fixtureDirectory.exists()) {
          await fixtureDirectory.delete(recursive: true);
        }
      });

      final missingImagePath =
          '${fixtureDirectory.path}${Platform.pathSeparator}missing.png';
      await expectLater(
        () => TesseractOcr.extractText(missingImagePath),
        throwsA(isA<FileSystemException>()),
      );

      final corruptImageFile = File(
        '${fixtureDirectory.path}${Platform.pathSeparator}corrupt.png',
      );
      await corruptImageFile.writeAsString('not a valid image');
      await expectLater(
        () => TesseractOcr.extractText(corruptImageFile.path),
        throwsA(isA<PlatformException>()),
      );

      await expectLater(
        () => TesseractOcr.extractText(
          corruptImageFile.path,
          config: const OCRConfig(engine: OCREngine.vision),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
