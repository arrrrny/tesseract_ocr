import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/src/ocr_options.dart';

void main() {
  // The literals the native plugins compare against, spelled out here so the
  // guard below cannot pass by reading them back from the same constant.
  const pageSegModeKey = 'tessedit_pageseg_mode';
  const recognitionLevelKey = 'recognition_level';
  const usesLanguageCorrectionKey = 'uses_language_correction';
  group('OcrOptionSpec.forAndroid', () {
    test('resolves the page segmentation mode to a PSM integer', () {
      final spec = OcrOptionSpec.forAndroid(<String, dynamic>{
        TesseractConfig.pageSegMode: PageSegmentationMode.singleLine,
      });

      expect(spec.rawPageSegMode, '7');
      expect(OcrOptionSpec.pageSegModeFor(spec.rawPageSegMode), 7);
      expect(spec.variables, isEmpty);
      expect(spec.hasIgnoredOptions, isFalse);
    });

    test('accepts an int page segmentation mode', () {
      final spec = OcrOptionSpec.forAndroid(<String, dynamic>{
        TesseractConfig.pageSegMode: 13,
      });

      expect(spec.rawPageSegMode, '13');
      expect(OcrOptionSpec.pageSegModeFor(spec.rawPageSegMode), 13);
    });

    test('reports no page segmentation mode when none was requested', () {
      final spec = OcrOptionSpec.forAndroid(<String, dynamic>{
        TesseractConfig.preserveInterwordSpaces: '1',
      });

      expect(spec.rawPageSegMode, isNull);
    });

    test('keeps an out-of-range page segmentation mode as ignored', () {
      final spec = OcrOptionSpec.forAndroid(<String, dynamic>{
        TesseractConfig.pageSegMode: '42',
      });

      expect(OcrOptionSpec.pageSegModeFor(spec.rawPageSegMode), isNull);
      expect(spec.variables, isEmpty);
      expect(spec.hasIgnoredOptions, isTrue);
      expect(spec.ignoredKeys, <String>[TesseractConfig.pageSegMode]);
    });

    test('passes every non-reserved option through as a variable', () {
      final spec = OcrOptionSpec.forAndroid(<String, dynamic>{
        TesseractConfig.preserveInterwordSpaces: '1',
        'tessedit_char_whitelist': '0123456789',
        'user_defined_dpi': 300,
      });

      expect(spec.variables, <String, String>{
        'preserve_interword_spaces': '1',
        'tessedit_char_whitelist': '0123456789',
        'user_defined_dpi': '300',
      });
      expect(spec.hasIgnoredOptions, isFalse);
    });

    test('excludes the keys the plugin consumes itself', () {
      final spec = OcrOptionSpec.forAndroid(<String, dynamic>{
        'language': 'eng',
        'engine': 'tesseract',
        'tessDataPath': '/tmp/tessdata',
        TesseractConfig.ocrEngineMode: '1',
        TesseractConfig.preserveInterwordSpaces: '1',
      });

      expect(spec.variables, <String, String>{
        'preserve_interword_spaces': '1',
      });
      expect(spec.hasIgnoredOptions, isFalse);
    });

    test('a null option value is reported as ignored, never as an empty value',
        () {
      final spec = OcrOptionSpec.forAndroid(<String, dynamic>{
        'preserve_interword_spaces': null,
      });

      expect(spec.variables, isEmpty);
      expect(spec.ignoredKeys, <String>['preserve_interword_spaces']);
    });

    test('no options at all leaves the engine on its default PSM', () {
      final spec = OcrOptionSpec.forAndroid(null);

      expect(spec.rawPageSegMode, isNull);
      expect(spec.variables, isEmpty);
      expect(spec.hasIgnoredOptions, isFalse);
    });
  });

  group('OcrOptionSpec.forVision', () {
    test('keeps the recognition level', () {
      final spec = OcrOptionSpec.forVision(<String, dynamic>{
        TesseractConfig.recognitionLevel: 'fast',
      });

      expect(spec.values, <String, String>{'recognition_level': 'fast'});
      expect(spec.hasIgnoredOptions, isFalse);
    });

    test('keeps a boolean language correction flag', () {
      expect(
        OcrOptionSpec.forVision(<String, dynamic>{
          TesseractConfig.usesLanguageCorrection: false,
        }).values,
        <String, String>{'uses_language_correction': 'false'},
      );
      expect(
        OcrOptionSpec.forVision(<String, dynamic>{
          TesseractConfig.usesLanguageCorrection: 'true',
        }).values,
        <String, String>{'uses_language_correction': 'true'},
      );
    });

    test('reports Tesseract-only keys as ignored instead of dropping them', () {
      final spec = OcrOptionSpec.forVision(<String, dynamic>{
        TesseractConfig.pageSegMode: '6',
        TesseractConfig.preserveInterwordSpaces: '1',
      });

      expect(spec.values, isEmpty);
      expect(spec.ignoredKeys, <String>[
        'tessedit_pageseg_mode',
        'preserve_interword_spaces',
      ]);
      expect(spec.hasIgnoredOptions, isTrue);
    });

    test('an unparsable boolean is ignored rather than guessed', () {
      final spec = OcrOptionSpec.forVision(<String, dynamic>{
        TesseractConfig.usesLanguageCorrection: 'maybe',
      });

      expect(spec.values, isEmpty);
      expect(spec.ignoredKeys, <String>['uses_language_correction']);
    });
  });

  group('Vision option readers', () {
    test('recognition level defaults to accurate', () {
      expect(
        OcrOptionSpec.visionRecognitionLevel(null),
        VisionRecognitionLevel.accurate,
      );
      expect(
        OcrOptionSpec.visionRecognitionLevel(<String, dynamic>{
          TesseractConfig.recognitionLevel: 'accurate',
        }),
        VisionRecognitionLevel.accurate,
      );
      expect(
        OcrOptionSpec.visionRecognitionLevel(<String, dynamic>{
          TesseractConfig.recognitionLevel: 'nonsense',
        }),
        VisionRecognitionLevel.accurate,
      );
    });

    test('recognition level fast is honoured', () {
      expect(
        OcrOptionSpec.visionRecognitionLevel(<String, dynamic>{
          TesseractConfig.recognitionLevel: 'fast',
        }),
        VisionRecognitionLevel.fast,
      );
    });

    test('language correction defaults to on', () {
      expect(OcrOptionSpec.visionUsesLanguageCorrection(null), isTrue);
      expect(
        OcrOptionSpec.visionUsesLanguageCorrection(<String, dynamic>{
          TesseractConfig.usesLanguageCorrection: '0',
        }),
        isFalse,
      );
    });
  });

  group('the option keys the native plugins are documented to honour', () {
    test('the PSM key matches the key the plugins switch on', () async {
      // The Android and macOS/Linux plugins compare against these literals in
      // their own languages; a rename on the Dart side must not silently turn
      // every caller's page segmentation mode into a no-op.
      final android = await File(
        'android/src/main/java/io/paratoner/tesseract_ocr/OcrOptions.java',
      ).readAsString();
      expect(
        android,
        contains('"$pageSegModeKey"'),
        reason: 'Android OcrOptions must switch on $pageSegModeKey',
      );

      // Both Apple platforms now run the shared Swift plugin, which forwards
      // every caller option (the page segmentation mode included) to the engine
      // with TessBaseAPISetVariable instead of building a command line.
      final apple = await File(
        'Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift',
      ).readAsString();
      expect(
        apple,
        contains('TessBaseAPISetVariable(tessBaseAPI, key, strValue)'),
        reason: 'the shared Apple plugin must set $pageSegModeKey as a Tesseract '
            'variable, which is how the PSM reaches the engine on iOS and macOS',
      );
      expect(
        apple,
        contains('applyTesseractVariables(options, to: tessBaseAPI)'),
        reason: 'the OCR and OSD paths must both apply the caller options',
      );
    });

    test('the Vision option keys are the ones the iOS plugin resolves',
        () async {
      final ios = await File(
        // Master moved the iOS plugin into the Swift package layout
        // (Sources/tesseract_ocr/) when it dropped ios/Classes/.
        'Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift',
      ).readAsString();
      expect(ios, contains('case "$recognitionLevelKey"'));
      expect(ios, contains('case "$usesLanguageCorrectionKey"'));
    });

    test("the Android reserved keys match the Java plugin's literals",
        () async {
      // OcrOptions.java spells RESERVED_KEYS as literals while the Dart side
      // uses TesseractConfig constants; a rename here must not silently turn a
      // reserved key into a forwarded Tesseract variable on Android.
      final java = await File(
        'android/src/main/java/io/paratoner/tesseract_ocr/OcrOptions.java',
      ).readAsString();
      for (final key in OcrOptionSpec.androidReservedKeys) {
        expect(
          java,
          contains('"$key"'),
          reason: 'Android OcrOptions.java must reserve $key',
        );
      }
    });
  });

  group('pageSegModeFor', () {
    test('parses integers and numeric strings', () {
      expect(OcrOptionSpec.pageSegModeFor(7), 7);
      expect(OcrOptionSpec.pageSegModeFor('7'), 7);
      expect(OcrOptionSpec.pageSegModeFor(' 7 '), 7);
    });

    test('rejects non-numeric and out-of-range values', () {
      expect(OcrOptionSpec.pageSegModeFor('auto'), isNull);
      expect(OcrOptionSpec.pageSegModeFor(-1), isNull);
      expect(OcrOptionSpec.pageSegModeFor(14), isNull);
      expect(OcrOptionSpec.pageSegModeFor(null), isNull);
    });
  });
}
