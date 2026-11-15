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
      if (call.method == 'extractHocr') {
        return "<span class='ocr_line'>recognized</span>";
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

  test('pubspec.yaml registers ios as a supported plugin platform', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('ios:'));
    expect(
      pubspec,
      matches(RegExp(r'ios:\s*\n\s*pluginClass:\s*TesseractOcrPlugin')),
    );
  });

  test('pubspec.yaml does not claim a shared-Darwin source without a darwin/ dir',
      () async {
    // Flutter resolves a `sharedDarwinSource: true` platform to
    // `<plugin>/darwin/<name>.podspec` and `<plugin>/darwin/<name>/Package.swift`
    // (flutter_tools plugins.dart `_darwinPluginDirectoryName`, and
    // bin/podhelper.rb `platform_directory = shared_darwin_source ? 'darwin' : platform`).
    // This plugin ships ios/ and macos/, so the flag pointed macOS at a directory
    // that does not exist and `pod install` failed with "No podspec found for
    // tesseract_ocr" before any pod was considered.
    final pubspec = await File('pubspec.yaml').readAsString();
    final macos = RegExp(
      r'macos:\s*\n\s*pluginClass:\s*TesseractOcrPlugin',
    ).firstMatch(pubspec);
    expect(macos, isNotNull, reason: 'pubspec.yaml must register macOS');

    final block = pubspec.substring(macos!.start);
    expect(
      block,
      isNot(contains('sharedDarwinSource: true')),
      reason: 'macOS must resolve to macos/tesseract_ocr.podspec, not a '
          'darwin/ directory this plugin does not ship',
    );
  });

  test('Package.swift declares SwiftyTesseract dependency for Apple platforms',
      () async {
    final packageSwift = await File('Package.swift').readAsString();
    expect(packageSwift,
        contains('https://github.com/SwiftyTesseract/SwiftyTesseract.git'));
    expect(
        packageSwift,
        contains(
            '.product(name: "SwiftyTesseract", package: "SwiftyTesseract")'));
  });

  test(
      'iOS Swift plugin validates tessData directory and traineddata files before initializing Tesseract',
      () async {
    final swiftSource =
        await File('Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift')
            .readAsString();
    expect(
      swiftSource,
      contains('func validateTessData'),
    );
    expect(
      swiftSource,
      contains('TESSDATA_NOT_FOUND'),
    );
  });

  // These guards pin the review-fix invariants in the Swift source itself, so a
  // regression that reintroduces a blocker (a non-compiling enum case, a
  // use-after-free defer, a dead binding) fails a test rather than only a real
  // `swift build` on macOS. They are not a substitute for that build gate
  // (.github/workflows/ci.yml), but they catch the regressions this PR is about.
  group('iOS Swift plugin source invariants', () {
    late String swiftSource;

    setUp(() async {
      swiftSource = await File(
        'Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift',
      ).readAsString();
    });

    test(
        'uses the real EngineMode case (.default), not a non-existent .defaultEngine',
        () {
      expect(swiftSource, isNot(contains('engineMode = .defaultEngine')));
      expect(swiftSource, contains('engineMode = .default'));
    });

    test(
        'creates and releases the TessBaseAPI handle inside the dispatched OCR closure',
        () {
      // The create/defer must live inside the DispatchQueue.async block, not at
      // function scope (which would end the handle before the async OCR runs).
      final asyncBlock = swiftSource.substring(
        swiftSource.indexOf('DispatchQueue(label: "com.tesseract.ocr"'),
      );
      expect(asyncBlock, contains('TessBaseAPICreate()'));
      expect(asyncBlock, contains('TessBaseAPIEnd(tessBaseAPI)'));
      expect(asyncBlock, contains('TessBaseAPIDelete(tessBaseAPI)'));
    });

    test('does not depend on OCREngineConfig (not in scope under SPM)', () {
      expect(swiftSource, isNot(contains('OCREngineConfig')));
    });

    test('does not keep the unused languageCodes binding', () {
      expect(swiftSource, isNot(contains('let languageCodes')));
    });

    test('pixReadMem receives an explicitly-bound UnsafePointer<UInt8>', () {
      expect(swiftSource, contains('assumingMemoryBound(to: UInt8.self)'));
    });
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
    // A device tessdata directory is the download-on-demand layout of #56: the
    // files are already there, so no asset copy runs and the directory the
    // engine is pointed at is the one that holds them.
    await File('$customTessData/eng.traineddata')
        .writeAsBytes(<int>[1, 2, 3, 4]);

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

  test('extractText points the engine at the tessdata subdirectory', () async {
    final imageFile = File('${tempDir.path}/sample.png');
    await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

    final deviceTessData = '${tempDir.path}/downloaded';
    await Directory('$deviceTessData/tessdata').create(recursive: true);
    await File('$deviceTessData/tessdata/eng.traineddata')
        .writeAsBytes(<int>[1, 2, 3, 4]);

    await TesseractOcr.extractText(
      imageFile.path,
      config: OCRConfig(
        language: 'eng',
        engine: OCREngine.tesseract,
        tessDataPath: deviceTessData,
      ),
    );

    final args = Map<String, dynamic>.from(
      recordedCalls.single.arguments as Map,
    );
    expect(args['tessData'], '$deviceTessData/tessdata');
  });

  test('extractText rejects a tessDataPath with no traineddata before any call',
      () async {
    final imageFile = File('${tempDir.path}/sample.png');
    await imageFile.writeAsBytes(<int>[137, 80, 78, 71]);

    final emptyTessData = '${tempDir.path}/empty_tessdata';
    await Directory(emptyTessData).create(recursive: true);

    await expectLater(
      () => TesseractOcr.extractText(
        imageFile.path,
        config: OCRConfig(
          language: 'eng',
          engine: OCREngine.tesseract,
          tessDataPath: emptyTessData,
        ),
      ),
      throwsA(
        isA<PlatformException>()
            .having(
              (PlatformException error) => error.code,
              'code',
              'tessdata-path-invalid',
            )
            .having(
              (PlatformException error) => error.message,
              'message',
              contains('eng.traineddata'),
            ),
      ),
    );
    expect(recordedCalls, isEmpty);
  });

  test('extractText leaves a Web tessDataPath URL untouched', () async {
    TesseractOcr.debugIsWebOverride = true;

    await TesseractOcr.extractText(
      'blob:https://example.com/1234',
      config: const OCRConfig(
        language: 'eng',
        engine: OCREngine.tesseract,
        tessDataPath: 'https://cdn.example.com/tessdata',
      ),
    );

    final args = Map<String, dynamic>.from(
      recordedCalls.single.arguments as Map,
    );
    expect(args['tessData'], 'https://cdn.example.com/tessdata');
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

  test('extractHocr returns the hOCR payload and calls the extractHocr method',
      () async {
    TesseractOcr.debugIsWebOverride = true;

    final result = await TesseractOcr.extractHocr(
      'blob:https://example.com/1234',
      config: const OCRConfig(
        language: 'eng',
        engine: OCREngine.tesseract,
        options: <String, dynamic>{
          TesseractConfig.pageSegMode: PageSegmentationMode.singleBlock,
        },
      ),
    );

    expect(result, contains('ocr_line'));
    expect(recordedCalls, hasLength(1));
    expect(recordedCalls.single.method, 'extractHocr');
    final args = Map<String, dynamic>.from(
      recordedCalls.single.arguments as Map,
    );
    expect(args['imagePath'], 'blob:https://example.com/1234');
    expect(args['language'], 'eng');
    expect(args['engine'], 'tesseract');
    expect(args['options'], <String, dynamic>{
      'tessedit_pageseg_mode': '6',
    });
  });

  test('extractHocr rejects Apple Vision engine on every platform', () async {
    TesseractOcr.debugIsWebOverride = true;

    await expectLater(
      () => TesseractOcr.extractHocr(
        'blob:https://example.com/1234',
        config: const OCRConfig(engine: OCREngine.vision),
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(recordedCalls, isEmpty);
  });

  test(
      'extractHocr copies tessdata from assets on IO when tessDataPath is null',
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

    final result = await TesseractOcr.extractHocr(imageFile.path);

    expect(result, contains('ocr_line'));
    expect(recordedCalls, hasLength(1));
    expect(recordedCalls.single.method, 'extractHocr');
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

  test('extractText still calls the extractText method (regression guard)',
      () async {
    TesseractOcr.debugIsWebOverride = true;

    final result = await TesseractOcr.extractText(
      'blob:https://example.com/1234',
      config: const OCRConfig(engine: OCREngine.tesseract),
    );

    expect(result, 'recognized text');
    expect(recordedCalls, hasLength(1));
    expect(recordedCalls.single.method, 'extractText');
  });

  group('hOCR native source invariants', () {
    test('iOS Swift plugin handles extractHocr and emits HOCR text', () async {
      final swiftSource = await File(
        'Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift',
      ).readAsString();
      expect(swiftSource, contains('case "extractHocr"'));
      expect(swiftSource, contains('TessBaseAPIGetHOCRText'));
    });

    test('Linux plugin honours the hOCR request and emits HOCR text', () async {
      final ccSource =
          await File('linux/tesseract_ocr_plugin.cc').readAsString();
      // The recognize() helper must be told which format to produce; an
      // always-UTF8 implementation would return plain text for an extractHocr
      // call, which is the gap this feature closes.
      expect(ccSource, contains('TessBaseAPIGetHOCRText'));
      expect(ccSource, contains('bool hocr'));
    });
  });
}
