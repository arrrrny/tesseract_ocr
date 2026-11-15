import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/src/web_helper.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

/// The image-bytes entry point (issue #55): a camera-first caller has the bytes
/// in memory and must not have to write a temporary file first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('tesseract_ocr');
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory tempDir;
  final List<MethodCall> recordedCalls = <MethodCall>[];

  /// A minimal PNG header — enough to prove the bytes travel unmodified.
  final Uint8List imageBytes = Uint8List.fromList(<int>[137, 80, 78, 71, 13]);

  setUp(() async {
    recordedCalls.clear();
    tempDir =
        await Directory.systemTemp.createTemp('tesseract_ocr_bytes_test_');

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
      if (call.method == 'extractText') {
        return 'recognized text';
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

  /// Mocks the tessdata assets so the IO platforms resolve a tessdata dir
  /// instead of throwing on a bundle that carries none.
  void mockTessDataAssets() {
    final Uint8List fakeTrainedData = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final Uint8List configBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'files': <String>['eng.traineddata'],
        }),
      ),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final String key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'assets/tessdata_config.json') {
        return ByteData.sublistView(configBytes);
      }
      if (key == 'assets/tessdata/eng.traineddata') {
        return ByteData.sublistView(fakeTrainedData);
      }
      return null;
    });
  }

  Map<String, dynamic> singleCallArguments() {
    expect(recordedCalls, hasLength(1));
    return Map<String, dynamic>.from(
      recordedCalls.single.arguments as Map,
    );
  }

  group('TesseractOcr.extractTextFromBytes', () {
    test('rejects empty bytes without touching the platform', () async {
      await expectLater(
        () => TesseractOcr.extractTextFromBytes(Uint8List(0)),
        throwsA(isA<ArgumentError>()),
      );
      expect(recordedCalls, isEmpty);
    });

    test('sends the bytes, not a path, and no file is written', () async {
      mockTessDataAssets();

      final String result = await TesseractOcr.extractTextFromBytes(imageBytes);

      expect(result, 'recognized text');
      final Map<String, dynamic> args = singleCallArguments();
      expect(args['imageBytes'], imageBytes);
      expect(args.containsKey('imagePath'), isFalse);
      expect(args['language'], 'eng');
      expect(args['engine'], 'defaultEngine');
      expect(args['tessData'], tempDir.path);
      // The tessdata copy the Tesseract engine needs still happens; the image
      // itself is never materialised on disk.
      expect(
        File('${tempDir.path}/tessdata/eng.traineddata').existsSync(),
        isTrue,
      );
      expect(
        Directory(tempDir.path)
            .listSync()
            .map((FileSystemEntity entity) =>
                entity.path.split(Platform.pathSeparator).last)
            .toSet(),
        <String>{'tessdata'},
      );
    });

    test('passes config language, engine, tessDataPath, and options through',
        () async {
      final String customTessData = '${tempDir.path}/custom_tessdata';
      await Directory(customTessData).create(recursive: true);

      final String result = await TesseractOcr.extractTextFromBytes(
        imageBytes,
        config: OCRConfig(
          language: 'eng',
          engine: OCREngine.tesseract,
          tessDataPath: customTessData,
          options: <String, dynamic>{
            TesseractConfig.preserveInterwordSpaces: '1',
            TesseractConfig.pageSegMode: PageSegmentationMode.singleBlock,
          },
        ),
      );

      expect(result, 'recognized text');
      final Map<String, dynamic> args = singleCallArguments();
      expect(args['imageBytes'], imageBytes);
      expect(args.containsKey('imagePath'), isFalse);
      expect(args['language'], 'eng');
      expect(args['engine'], 'tesseract');
      expect(args['tessData'], customTessData);
      expect(args['options'], <String, dynamic>{
        'preserve_interword_spaces': '1',
        'tessedit_pageseg_mode': '6',
      });
    });

    test('rejects the Apple Vision engine on Web', () async {
      TesseractOcr.debugIsWebOverride = true;

      await expectLater(
        () => TesseractOcr.extractTextFromBytes(
          imageBytes,
          config: const OCRConfig(engine: OCREngine.vision),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(recordedCalls, isEmpty);
    });

    test('rejects the Apple Vision engine on macOS', () async {
      TesseractOcr.debugIsMacOSOverride = true;
      mockTessDataAssets();

      await expectLater(
        () => TesseractOcr.extractTextFromBytes(
          imageBytes,
          config: const OCRConfig(engine: OCREngine.vision),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(recordedCalls, isEmpty);
    });

    test('the path entry point still sends imagePath and no bytes', () async {
      mockTessDataAssets();
      final File imageFile = File('${tempDir.path}/sample.png');
      await imageFile.writeAsBytes(imageBytes);

      await TesseractOcr.extractText(imageFile.path);

      final Map<String, dynamic> args = singleCallArguments();
      expect(args['imagePath'], imageFile.path);
      expect(args.containsKey('imageBytes'), isFalse);
    });
  });

  group('TesseractWebHelper.resolveImageBytes', () {
    test('reads the bytes a channel call carries', () {
      expect(
        TesseractWebHelper.resolveImageBytes(imageBytes),
        imageBytes,
      );
      expect(
        TesseractWebHelper.resolveImageBytes(imageBytes.buffer),
        imageBytes,
      );
      expect(
        TesseractWebHelper.resolveImageBytes(
          ByteData.sublistView(imageBytes),
        ),
        imageBytes,
      );
    });

    test('is null for anything that is not image bytes', () {
      expect(TesseractWebHelper.resolveImageBytes(null), isNull);
      expect(TesseractWebHelper.resolveImageBytes('assets/a.png'), isNull);
      expect(TesseractWebHelper.resolveImageBytes(42), isNull);
    });
  });

  // The native plugins are not compiled by this suite (nothing here builds
  // Android, iOS, macOS or Linux), so the channel contract each one must honour
  // is pinned on its source — the same guard the iOS invariants group applies.
  group('native plugins read the imageBytes channel argument', () {
    test('the web plugin hands tesseract.js the bytes', () async {
      final String source =
          await File('lib/tesseract_ocr_web.dart').readAsString();
      expect(source, contains('imageBytes'));
      expect(source, contains('TesseractWebHelper.resolveImageBytes'));
    });

    test('the Android plugin decodes the bytes for TessBaseAPI', () async {
      final String plugin = await File(
        'android/src/main/java/io/paratoner/tesseract_ocr/TesseractOcrPlugin.java',
      ).readAsString();
      expect(plugin, contains('imageBytes'));
      expect(plugin, contains('setImageBytes'));

      final String api = await File(
        'android/src/main/java/io/paratoner/tesseract_ocr/NativeOcrApi.java',
      ).readAsString();
      expect(api, contains('void setImageBytes(byte[] bytes);'));
    });

    test('the shared Apple plugin takes bytes straight to pixReadMem',
        () async {
      final String source = await File(
        'Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift',
      ).readAsString();
      expect(source, contains('imageBytes'));
      // Both engines must accept bytes: the Tesseract path decodes the buffer,
      // the Vision path wraps it in a UIImage.
      expect(source, contains('UIImage(data:'));
    });

    test('the Linux plugin accepts bytes too', () async {
      final String source =
          await File('linux/tesseract_ocr_plugin.cc').readAsString();
      expect(source, contains('imageBytes'));
      expect(source, contains('fl_value_get_uint8_list'));
    });
  });
}
