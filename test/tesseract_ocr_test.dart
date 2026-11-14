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
    TesseractOcr.debugIsMacOSOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('pubspec.yaml registers macos as a supported plugin platform', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('macos:'));
    expect(
      pubspec,
      matches(RegExp(r'macos:\s*\n\s*pluginClass:\s*TesseractOcrPlugin')),
    );
  });

  test('extractText throws FileSystemException for missing image file',
      () async {
    final missingPath = '${tempDir.path}/does_not_exist.png';
    await expectLater(
      () => TesseractOcr.extractText(missingPath),
      throwsA(isA<FileSystemException>()),
    );
    expect(recordedCalls, isEmpty);
  });

  test('extractText copies tessdata from assets when tessDataPath is omitted',
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
    expect(await copiedFile.exists(), isTrue);
    expect(await copiedFile.readAsBytes(), fakeTrainedData);
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
