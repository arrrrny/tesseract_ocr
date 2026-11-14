import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tesseract_ocr/src/tessdata_assets.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

/// Regression tests for the asset -> documents copy that feeds the native
/// Tesseract engine (issue #52): a traineddata file that never lands in the
/// tessdata directory makes Tesseract initialize on an empty tessdata dir, so
/// recognition returns garbage while the tessdata path still looks valid.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('tesseract_ocr');
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory tempDir;

  /// The asset bundle's answer per key; a `null` return simulates an asset the
  /// bundle does not carry at all.
  late ByteData? Function(String key) resolveAsset;

  ByteData configAsset(Object files) => ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(jsonEncode(<String, dynamic>{'files': files})),
        ),
      );

  ByteData trainedDataAsset(List<int> bytes) =>
      ByteData.sublistView(Uint8List.fromList(bytes));

  /// Serves [eng] for `eng.traineddata` and nothing for any other traineddata.
  void serveEngOnly(List<int> eng) {
    resolveAsset = (String key) {
      if (key == 'assets/tessdata_config.json') {
        return configAsset(<String>['eng.traineddata']);
      }
      if (key == 'assets/tessdata/eng.traineddata') {
        return trainedDataAsset(eng);
      }
      return null;
    };
  }

  Future<File> writeImage() async {
    final File image = File('${tempDir.path}/sample.png');
    await image.writeAsBytes(<int>[137, 80, 78, 71]);
    return image;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tessdata_assets_test_');
    resolveAsset = (_) => null;
    // A successful config read is cached on the bundle for the whole test
    // process, so each test has to start from an empty cache.
    (rootBundle as CachingAssetBundle).clear();

    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel,
        (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'extractText') {
        return 'recognized text';
      }
      return null;
    });
    // Registered once for the whole file: a handler removed and re-set between
    // tests stops being consulted by the messenger at all.
    messenger.setMockMessageHandler('flutter/assets',
        (ByteData? message) async {
      return resolveAsset(utf8.decode(message!.buffer.asUint8List()));
    });
  });

  tearDown(() async {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('tessdata copy from assets', () {
    test('throws when tessdata_config.json is not carried by the bundle',
        () async {
      final File image = await writeImage();

      await expectLater(
        () => TesseractOcr.extractText(image.path),
        throwsA(
          isA<PlatformException>()
              .having(
                (PlatformException e) => e.code,
                'code',
                TessDataAssets.invalidAssetCode,
              )
              .having(
                (PlatformException e) => e.message,
                'message',
                allOf(
                  contains('assets/tessdata_config.json'),
                  contains('pubspec.yaml'),
                ),
              ),
        ),
      );
    });

    test('throws naming the traineddata asset the bundle does not carry',
        () async {
      final File image = await writeImage();
      resolveAsset = (String key) {
        if (key == 'assets/tessdata_config.json') {
          return configAsset(<String>['eng.traineddata', 'deu.traineddata']);
        }
        if (key == 'assets/tessdata/eng.traineddata') {
          return trainedDataAsset(<int>[1, 2, 3, 4]);
        }
        return null;
      };

      await expectLater(
        () => TesseractOcr.extractText(image.path),
        throwsA(
          isA<PlatformException>()
              .having(
                (PlatformException e) => e.code,
                'code',
                TessDataAssets.invalidAssetCode,
              )
              .having(
                (PlatformException e) => e.message,
                'message',
                allOf(
                  contains('assets/tessdata/deu.traineddata'),
                  contains('pubspec.yaml'),
                ),
              ),
        ),
      );
      expect(
        File('${tempDir.path}/tessdata/deu.traineddata').existsSync(),
        isFalse,
      );
    });

    test('throws when a declared traineddata asset is empty', () async {
      final File image = await writeImage();
      serveEngOnly(<int>[]);

      await expectLater(
        () => TesseractOcr.extractText(image.path),
        throwsA(
          isA<PlatformException>().having(
            (PlatformException e) => e.message,
            'message',
            contains('assets/tessdata/eng.traineddata'),
          ),
        ),
      );
      expect(
        File('${tempDir.path}/tessdata/eng.traineddata').existsSync(),
        isFalse,
      );
    });

    test('replaces a zero-byte traineddata left by an earlier aborted copy',
        () async {
      final File image = await writeImage();
      final Directory tessdataDir = Directory('${tempDir.path}/tessdata');
      await tessdataDir.create(recursive: true);
      final File stale = File('${tessdataDir.path}/eng.traineddata');
      await stale.writeAsBytes(<int>[]);

      serveEngOnly(<int>[1, 2, 3, 4]);

      final String result = await TesseractOcr.extractText(image.path);

      expect(result, 'recognized text');
      expect(await stale.readAsBytes(), <int>[1, 2, 3, 4]);
    });

    test('replaces a truncated traineddata left by an earlier aborted copy',
        () async {
      final File image = await writeImage();
      final Directory tessdataDir = Directory('${tempDir.path}/tessdata');
      await tessdataDir.create(recursive: true);
      final File stale = File('${tessdataDir.path}/eng.traineddata');
      await stale.writeAsBytes(<int>[1, 2]);

      serveEngOnly(<int>[1, 2, 3, 4]);

      await TesseractOcr.extractText(image.path);

      expect(await stale.readAsBytes(), <int>[1, 2, 3, 4]);
    });

    test('keeps a traineddata that already matches the asset', () async {
      final File image = await writeImage();
      final Directory tessdataDir = Directory('${tempDir.path}/tessdata');
      await tessdataDir.create(recursive: true);
      final File copied = File('${tessdataDir.path}/eng.traineddata');
      await copied.writeAsBytes(<int>[1, 2, 3, 4]);

      serveEngOnly(<int>[1, 2, 3, 4]);

      await TesseractOcr.extractText(image.path);

      expect(await copied.readAsBytes(), <int>[1, 2, 3, 4]);
    });

    test('throws when tessdata_config.json lists no file', () async {
      final File image = await writeImage();
      resolveAsset = (String key) =>
          key == 'assets/tessdata_config.json' ? configAsset(<String>[]) : null;

      await expectLater(
        () => TesseractOcr.extractText(image.path),
        throwsA(
          isA<PlatformException>()
              .having(
                (PlatformException e) => e.code,
                'code',
                TessDataAssets.invalidConfigCode,
              )
              .having(
                (PlatformException e) => e.message,
                'message',
                contains('assets/tessdata_config.json'),
              ),
        ),
      );
    });

    test('throws when tessdata_config.json is not a JSON object', () async {
      final File image = await writeImage();
      resolveAsset = (String key) =>
          key == 'assets/tessdata_config.json' ? ByteData(0) : null;

      await expectLater(
        () => TesseractOcr.extractText(image.path),
        throwsA(
          isA<PlatformException>().having(
            (PlatformException e) => e.code,
            'code',
            TessDataAssets.invalidConfigCode,
          ),
        ),
      );
    });
  });

  group('TessDataAssets', () {
    test('parseFileNames reads the declared file names', () {
      expect(
        TessDataAssets.parseFileNames(
          '{"files": ["eng.traineddata", "deu.traineddata"]}',
          configAsset: 'assets/tessdata_config.json',
        ),
        <String>['eng.traineddata', 'deu.traineddata'],
      );
    });

    test('parseFileNames rejects a path that escapes the tessdata dir', () {
      expect(
        () => TessDataAssets.parseFileNames(
          '{"files": ["../secrets.traineddata"]}',
          configAsset: 'assets/tessdata_config.json',
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(
        () => TessDataAssets.parseFileNames(
          '{"files": ["/etc/passwd"]}',
          configAsset: 'assets/tessdata_config.json',
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(
        () => TessDataAssets.parseFileNames(
          '{"files": [""]}',
          configAsset: 'assets/tessdata_config.json',
        ),
        throwsA(isA<PlatformException>()),
      );
    });

    test('needsCopy compares the destination length to the asset length', () {
      expect(
        TessDataAssets.needsCopy(existingLength: null, assetLength: 4),
        isTrue,
      );
      expect(
        TessDataAssets.needsCopy(existingLength: 0, assetLength: 4),
        isTrue,
      );
      expect(
        TessDataAssets.needsCopy(existingLength: 2, assetLength: 4),
        isTrue,
      );
      expect(
        TessDataAssets.needsCopy(existingLength: 4, assetLength: 4),
        isFalse,
      );
    });

    test('validateTessDataFile rejects a missing or empty destination',
        () async {
      final Directory dir = await Directory.systemTemp.createTemp('tessdata_');
      addTearDown(() => dir.delete(recursive: true));
      final File empty = File('${dir.path}/empty.traineddata');
      await empty.writeAsBytes(<int>[]);
      final File missing = File('${dir.path}/missing.traineddata');

      expect(
        () => TessDataAssets.validateTessDataFile(
          empty,
          'assets/tessdata/empty.traineddata',
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(
        () => TessDataAssets.validateTessDataFile(
          missing,
          'assets/tessdata/missing.traineddata',
        ),
        throwsA(isA<PlatformException>()),
      );
      await empty.writeAsBytes(<int>[1]);
      expect(
        () => TessDataAssets.validateTessDataFile(
          empty,
          'assets/tessdata/empty.traineddata',
        ),
        returnsNormally,
      );
    });
  });
}
