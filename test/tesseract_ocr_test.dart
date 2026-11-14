import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/src/web_helper.dart';
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
    tempDir = await Directory.systemTemp.createTemp('tesseract_ocr_test_');

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

  test('pubspec.yaml registers web as a supported plugin platform', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('flutter_web_plugins:'));
    expect(
      pubspec,
      matches(
        RegExp(
          r'web:\s*\n\s*pluginClass:\s*TesseractOcrWeb\s*\n\s*fileName:\s*tesseract_ocr_web\.dart',
        ),
      ),
    );
  });

  test('pubspec.yaml registers macos as a supported plugin platform', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('macos:'));
    expect(
      pubspec,
      matches(RegExp(r'macos:\s*\n\s*pluginClass:\s*TesseractOcrPlugin')),
    );
  });

  test('extractText throws ArgumentError on IO when image file is missing',
      () async {
    final missingPath = '${tempDir.path}/does_not_exist.png';
    await expectLater(
      () => TesseractOcr.extractText(missingPath),
      throwsA(isA<ArgumentError>()),
    );
    expect(recordedCalls, isEmpty);
  });

  test('extractText rejects Apple Vision engine on Web', () async {
    TesseractOcr.debugIsWebOverride = true;

    await expectLater(
      () => TesseractOcr.extractText(
        'blob:https://example.com/1234',
        config: const OCRConfig(engine: OCREngine.vision),
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(recordedCalls, isEmpty);
  });

  test('extractText allows blob/data/http URLs on Web without IO file check',
      () async {
    TesseractOcr.debugIsWebOverride = true;

    final result = await TesseractOcr.extractText(
      'blob:https://example.com/1234',
      config: const OCRConfig(
        language: 'eng',
        engine: OCREngine.tesseract,
        options: <String, dynamic>{
          TesseractConfig.preserveInterwordSpaces: '1',
          TesseractConfig.pageSegMode: PageSegmentationMode.singleBlock,
        },
      ),
    );

    expect(result, 'recognized text');
    expect(recordedCalls, hasLength(1));
    final args = Map<String, dynamic>.from(
      recordedCalls.single.arguments as Map,
    );
    expect(args['imagePath'], 'blob:https://example.com/1234');
    expect(args['language'], 'eng');
    expect(args['engine'], 'tesseract');
    expect(args['tessData'], isNull);
    expect(args['options'], <String, dynamic>{
      'preserve_interword_spaces': '1',
      'tessedit_pageseg_mode': '6',
    });
  });

  test(
      'extractText copies tessdata from assets on IO when tessDataPath is null',
      () async {
    final imageFile = File('${tempDir.path}/sample.png');
    await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

    final fakeTrainedData = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final configBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'files': <String>['eng.traineddata'],
        }),
      ),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'assets/tessdata_config.json') {
        return ByteData.sublistView(configBytes);
      }
      if (key == 'assets/tessdata/eng.traineddata') {
        return ByteData.sublistView(fakeTrainedData);
      }
      return null;
    });

    final result = await TesseractOcr.extractText(imageFile.path);

    expect(result, 'recognized text');
    expect(recordedCalls, hasLength(1));
    final args = Map<String, dynamic>.from(
      recordedCalls.single.arguments as Map,
    );
    expect(args['imagePath'], imageFile.path);
    expect(args['tessData'], tempDir.path);
    expect(args['language'], 'eng');
    expect(args['engine'], 'defaultEngine');

    final copiedFile = File('${tempDir.path}/tessdata/eng.traineddata');
    expect(copiedFile.existsSync(), isTrue);
    expect(await copiedFile.readAsBytes(), fakeTrainedData);
  });

  group('WebHelper', () {
    test('resolveLangPath strips trailing slash and resolves relative paths',
        () {
      final base = Uri.parse('https://example.com/app/index.html');
      expect(
        TesseractWebHelper.resolveLangPath(baseUri: base, overridePath: null),
        'https://example.com/app/assets/assets/tessdata',
      );
      expect(
        TesseractWebHelper.resolveLangPath(
          baseUri: base,
          overridePath: 'https://cdn.example.com/tessdata/',
        ),
        'https://cdn.example.com/tessdata',
      );
      expect(
        TesseractWebHelper.resolveLangPath(
          baseUri: base,
          overridePath: 'custom/tessdata/',
        ),
        'https://example.com/app/custom/tessdata',
      );
    });

    test('resolveOem uses OEM.DEFAULT (3) and legacy support by default', () {
      final defaultOem = TesseractWebHelper.resolveOem(null);
      expect(defaultOem.oem, 3);
      expect(defaultOem.useLegacy, isTrue);

      final lstmOnly = TesseractWebHelper.resolveOem(<String, dynamic>{
        TesseractConfig.ocrEngineMode: '1',
      });
      expect(lstmOnly.oem, 1);
      expect(lstmOnly.useLegacy, isFalse);
    });

    test('filterRuntimeOptions excludes reserved and init-only keys', () {
      final filtered =
          TesseractWebHelper.filterRuntimeOptions(<String, dynamic>{
        'language': 'eng',
        'engine': 'tesseract',
        'tessDataPath': '/tmp',
        TesseractConfig.ocrEngineMode: '1',
        TesseractConfig.pageSegMode: '6',
        TesseractConfig.preserveInterwordSpaces: '1',
      });
      expect(filtered, <String, String>{
        'tessedit_pageseg_mode': '6',
        'preserve_interword_spaces': '1',
      });
    });

    test('isDirectWebImageInput detects blob, data, and http(s) URLs', () {
      expect(
        TesseractWebHelper.isDirectWebImageInput('blob:http://localhost/abc'),
        isTrue,
      );
      expect(
        TesseractWebHelper.isDirectWebImageInput('data:image/png;base64,AAA='),
        isTrue,
      );
      expect(
        TesseractWebHelper.isDirectWebImageInput('https://example.com/a.png'),
        isTrue,
      );
      expect(
        TesseractWebHelper.isDirectWebImageInput(
          'packages/tesseract_ocr/images/testocr.png',
        ),
        isFalse,
      );
    });
  });

  test('extractText passes custom tessDataPath, engine, and options', () async {
    final imageFile = File('${tempDir.path}/sample.png');
    await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

    final customTessData = '${tempDir.path}/custom_tessdata';
    await Directory(customTessData).create(recursive: true);

    final result = await TesseractOcr.extractText(
      imageFile.path,
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
    expect(recordedCalls, hasLength(1));
    final args = Map<String, dynamic>.from(
      recordedCalls.single.arguments as Map,
    );
    expect(args['imagePath'], imageFile.path);
    expect(args['tessData'], customTessData);
    expect(args['language'], 'eng');
    expect(args['engine'], 'tesseract');
    expect(args['options'], <String, dynamic>{
      'preserve_interword_spaces': '1',
      'tessedit_pageseg_mode': '6',
    });
  });

  test('extractText rejects Apple Vision engine on macOS', () async {
    final imageFile = File('${tempDir.path}/sample.png');
    await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

    TesseractOcr.debugIsMacOSOverride = true;

    await expectLater(
      () => TesseractOcr.extractText(
        imageFile.path,
        config: const OCRConfig(
          language: 'eng',
          engine: OCREngine.vision,
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(recordedCalls, isEmpty);
  });
}
