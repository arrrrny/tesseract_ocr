import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('tesseract_ocr');
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory tempDir;
  final List<MethodCall> recordedCalls = <MethodCall>[];

  setUp(() async {
    recordedCalls.clear();
    tempDir = await Directory.systemTemp.createTemp('tesseract_ocr_osd_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      recordedCalls.add(call);
      if (call.method == 'detectOrientationScript') {
        return <String, dynamic>{
          'orientation': 90,
          'orientation_conf': 2.5,
          'script': 'Latin',
          'script_conf': 1.25,
        };
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    TesseractOcr.debugIsWebOverride = null;
    TesseractOcr.debugIsMacOSOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('OsdResult', () {
    test('fromMap reads the four OSD fields', () {
      final result = OsdResult.fromMap(<Object?, Object?>{
        'orientation': 180,
        'orientation_conf': 3.5,
        'script': 'Han',
        'script_conf': 4.25,
      });
      expect(result.orientationDegrees, 180);
      expect(result.orientationConfidence, 3.5);
      expect(result.scriptName, 'Han');
      expect(result.scriptConfidence, 4.25);
    });

    test('fromMap coerces stringified numbers and drops unknown keys', () {
      final result = OsdResult.fromMap(<Object?, Object?>{
        'orientation': '270',
        'orientation_conf': '1.75',
        'script': 'Cyrillic',
        'script_conf': 2,
        'unexpected': 'ignored',
      });
      expect(result.orientationDegrees, 270);
      expect(result.orientationConfidence, 1.75);
      expect(result.scriptName, 'Cyrillic');
      expect(result.scriptConfidence, 2.0);
    });

    test('fromMap defaults missing fields instead of throwing', () {
      final result = OsdResult.fromMap(<Object?, Object?>{});
      expect(result.orientationDegrees, 0);
      expect(result.orientationConfidence, 0);
      expect(result.scriptName, '');
      expect(result.scriptConfidence, 0);
    });

    test('fromMap maps non-finite numbers to the defaults', () {
      final result = OsdResult.fromMap(<Object?, Object?>{
        'orientation': double.nan,
        'orientation_conf': double.infinity,
        'script': double.nan,
        'script_conf': 'Infinity',
      });
      expect(result.orientationDegrees, 0);
      expect(result.orientationConfidence, 0);
      // A non-finite value must not stringify into the script name.
      expect(result.scriptName, '');
      expect(result.scriptConfidence, 0);
    });

    test('toMap round-trips the four OSD fields', () {
      const result = OsdResult(
        orientationDegrees: 90,
        orientationConfidence: 1.5,
        scriptName: 'Latin',
        scriptConfidence: 2.5,
      );
      expect(result.toMap(), <String, Object>{
        'orientation': 90,
        'orientation_conf': 1.5,
        'script': 'Latin',
        'script_conf': 2.5,
      });
    });
  });

  group('detectOrientationScript', () {
    test('throws ArgumentError on an empty image path', () async {
      await expectLater(
        () => TesseractOcr.detectOrientationAndScript('   '),
        throwsA(isA<ArgumentError>()),
      );
      expect(recordedCalls, isEmpty);
    });

    test('rejects the Apple Vision engine without touching the channel',
        () async {
      final imageFile = File('${tempDir.path}/sample.png');
      await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

      await expectLater(
        () => TesseractOcr.detectOrientationAndScript(
          imageFile.path,
          config: const OCRConfig(engine: OCREngine.vision),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(recordedCalls, isEmpty);
    });

    test('throws ArgumentError on IO when the image file is missing', () async {
      final missingPath = '${tempDir.path}/does_not_exist.png';
      await expectLater(
        () => TesseractOcr.detectOrientationAndScript(missingPath),
        throwsA(isA<ArgumentError>()),
      );
      expect(recordedCalls, isEmpty);
    });

    test('parses the native OSD map on IO', () async {
      final imageFile = File('${tempDir.path}/sample.png');
      await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

      final result = await TesseractOcr.detectOrientationAndScript(
        imageFile.path,
        config: OCRConfig(tessDataPath: tempDir.path),
      );

      expect(result.orientationDegrees, 90);
      expect(result.orientationConfidence, 2.5);
      expect(result.scriptName, 'Latin');
      expect(result.scriptConfidence, 1.25);

      expect(recordedCalls, hasLength(1));
      final call = recordedCalls.single;
      expect(call.method, 'detectOrientationScript');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['imagePath'], imageFile.path);
      expect(args['language'], 'eng');
      expect(args['engine'], 'defaultEngine');
    });

    test('copies tessdata from assets on IO when tessDataPath is null',
        () async {
      final imageFile = File('${tempDir.path}/sample.png');
      await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

      final fakeTrainedData = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final configBytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'files': <String>['eng.traineddata', 'osd.traineddata'],
          }),
        ),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key == 'assets/tessdata_config.json') {
          return ByteData.sublistView(configBytes);
        }
        if (key == 'assets/tessdata/eng.traineddata' ||
            key == 'assets/tessdata/osd.traineddata') {
          return ByteData.sublistView(fakeTrainedData);
        }
        return null;
      });

      final result = await TesseractOcr.detectOrientationAndScript(
        imageFile.path,
        config: const OCRConfig(language: 'osd'),
      );

      expect(result.scriptName, 'Latin');
      final args = Map<String, dynamic>.from(
        recordedCalls.single.arguments as Map,
      );
      expect(args['tessData'], tempDir.path);
      expect(args['language'], 'osd');
    });

    test('passes a custom tessDataPath and language through', () async {
      final imageFile = File('${tempDir.path}/sample.png');
      await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

      final customTessData = '${tempDir.path}/custom_tessdata';
      await Directory(customTessData).create(recursive: true);

      final result = await TesseractOcr.detectOrientationAndScript(
        imageFile.path,
        config: OCRConfig(language: 'osd', tessDataPath: customTessData),
      );

      expect(result.scriptName, 'Latin');
      final args = Map<String, dynamic>.from(
        recordedCalls.single.arguments as Map,
      );
      expect(args['tessData'], customTessData);
      expect(args['language'], 'osd');
    });

    test('allows blob URLs on Web without an IO file check', () async {
      TesseractOcr.debugIsWebOverride = true;

      final result = await TesseractOcr.detectOrientationAndScript(
        'blob:https://example.com/1234',
        config: const OCRConfig(language: 'osd', engine: OCREngine.tesseract),
      );

      expect(result.orientationDegrees, 90);
      expect(recordedCalls, hasLength(1));
      final args = Map<String, dynamic>.from(
        recordedCalls.single.arguments as Map,
      );
      expect(args['imagePath'], 'blob:https://example.com/1234');
      expect(args['tessData'], isNull);
    });

    test('defaults the language to osd when no config is given', () async {
      final imageFile = File('${tempDir.path}/sample.png');
      await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

      final fakeTrainedData = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final configBytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'files': <String>['eng.traineddata', 'osd.traineddata'],
          }),
        ),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key == 'assets/tessdata_config.json') {
          return ByteData.sublistView(configBytes);
        }
        if (key == 'assets/tessdata/eng.traineddata' ||
            key == 'assets/tessdata/osd.traineddata') {
          return ByteData.sublistView(fakeTrainedData);
        }
        return null;
      });

      await TesseractOcr.detectOrientationAndScript(imageFile.path);

      final args = Map<String, dynamic>.from(
        recordedCalls.single.arguments as Map,
      );
      // The OCR default `eng` is not a legacy-capable detector model, so the
      // OSD default is the `osd` model itself.
      expect(args['language'], 'osd');
    });

    test('forwards OCRConfig.options to the channel', () async {
      final imageFile = File('${tempDir.path}/sample.png');
      await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

      await TesseractOcr.detectOrientationAndScript(
        imageFile.path,
        config: const OCRConfig(
          language: 'osd',
          tessDataPath: '/unused',
          options: <String, dynamic>{'tessedit_pageseg_mode': '0'},
        ),
      );

      final args = Map<String, dynamic>.from(
        recordedCalls.single.arguments as Map,
      );
      expect(
        args['options'],
        <String, dynamic>{'tessedit_pageseg_mode': '0'},
      );
    });

    test('throws PlatformException when the engine returns no result',
        () async {
      final imageFile = File('${tempDir.path}/sample.png');
      await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        recordedCalls.add(call);
        return null;
      });

      await expectLater(
        () => TesseractOcr.detectOrientationAndScript(
          imageFile.path,
          config: OCRConfig(tessDataPath: tempDir.path),
        ),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('native OSD wiring (source invariants)', () {
    test('the Linux plugin handles detectOrientationScript via the C API',
        () async {
      final source = await File('linux/tesseract_ocr_plugin.cc').readAsString();
      expect(source, contains('"detectOrientationScript"'));
      expect(source, contains('TessBaseAPIDetectOrientationScript'));
    });

    test('the Apple plugin handles detectOrientationScript via the C API',
        () async {
      final source = await File(
        'Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift',
      ).readAsString();
      expect(source, contains('"detectOrientationScript"'));
      expect(source, contains('TessBaseAPIDetectOrientationScript'));
    });

    test('the macOS plugin answers detectOrientationScript explicitly',
        () async {
      final source = await File(
        'macos/tesseract_ocr/Sources/tesseract_ocr/TesseractOcrPlugin.swift',
      ).readAsString();
      expect(source, contains('"detectOrientationScript"'));
      // macOS drives the tesseract executable, which cannot return the
      // structured OSD result; the handler must answer a clear unsupported
      // error rather than letting the channel fall through to
      // FlutterMethodNotImplemented (a MissingPluginException on the caller).
      expect(source, contains('UNSUPPORTED_OSD'));
    });

    test('the web plugin maps tesseract.js detect() to the OSD fields',
        () async {
      final source = await File('lib/tesseract_ocr_web.dart').readAsString();
      expect(source, contains('detectOrientationScript'));
      expect(source, contains('detect'));
      expect(source, contains('orientation_degrees'));
      expect(source, contains('script_confidence'));
    });

    test('the Android plugin answers detectOrientationScript explicitly',
        () async {
      final source = await File(
        'android/src/main/java/io/paratoner/tesseract_ocr/TesseractOcrPlugin.java',
      ).readAsString();
      expect(source, contains('"detectOrientationScript"'));
      // The bundled tesseract4android binding exposes no OSD getter, so the
      // handler must answer a clear unsupported error rather than silently
      // succeeding.
      expect(source, contains('UNSUPPORTED_OSD'));
    });
  });
}
