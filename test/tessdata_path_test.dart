import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tesseract_ocr/src/io_helper_io.dart'
    if (dart.library.html) 'package:tesseract_ocr/src/io_helper_stub.dart';

/// The resolution of a caller-supplied tessdata directory (issue #56): a
/// download-on-demand flow points recognition at a directory that is already on
/// the device instead of shipping `.traineddata` as Flutter assets.
///
/// The directory either holds the `.traineddata` files itself or keeps them in a
/// `tessdata` subdirectory (the layout the asset copy produces), and anything
/// else is answered with a `PlatformException` naming the path — a native
/// `TESSDATA_NOT_FOUND` from the engine would tell the caller to bundle assets,
/// which is precisely the step this flow exists to skip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tessdata_path_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Writes [fileNames] into the [relative] directory under the temp root.
  Future<Directory> writeTrainedData(
    String relative,
    List<String> fileNames,
  ) async {
    final Directory dir = Directory(
      p.join(tempDir.path, relative),
    )..createSync(recursive: true);
    for (final String fileName in fileNames) {
      File(p.join(dir.path, fileName)).writeAsBytesSync(<int>[1, 2, 3, 4]);
    }
    return dir;
  }

  test('accepts a device directory that holds the traineddata directly',
      () async {
    final Directory dir = await writeTrainedData('langs', <String>[
      'eng.traineddata',
    ]);

    expect(
      await resolveTessDataDirectory(dir.path, language: 'eng'),
      dir.path,
    );
  });

  test('accepts a device directory with a tessdata subdirectory', () async {
    await writeTrainedData('langs/tessdata', <String>['eng.traineddata']);

    expect(
      await resolveTessDataDirectory(
        p.join(tempDir.path, 'langs'),
        language: 'eng',
      ),
      p.join(tempDir.path, 'langs', 'tessdata'),
    );
  });

  test('every language of a multi-language request must be present', () async {
    final Directory dir = await writeTrainedData('langs', <String>[
      'eng.traineddata',
      'deu.traineddata',
    ]);

    expect(
      await resolveTessDataDirectory(dir.path, language: 'eng+deu'),
      dir.path,
    );
  });

  test('a missing traineddata names the file and the directory', () async {
    final Directory dir = await writeTrainedData('langs', <String>[
      'deu.traineddata',
    ]);

    await expectLater(
      () => resolveTessDataDirectory(dir.path, language: 'eng+deu'),
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
              allOf(contains(dir.path), contains('eng.traineddata')),
            ),
      ),
    );
  });

  test('a directory that does not exist is rejected, not handed to the engine',
      () async {
    final String missing = p.join(tempDir.path, 'never-downloaded');

    await expectLater(
      () => resolveTessDataDirectory(missing, language: 'eng'),
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
              allOf(contains(missing), contains('eng.traineddata')),
            ),
      ),
    );
  });

  test('a path that is a file is rejected, not read as a directory', () async {
    final File file = File(p.join(tempDir.path, 'eng.traineddata'))
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);

    await expectLater(
      () => resolveTessDataDirectory(file.path, language: 'eng'),
      throwsA(
        isA<PlatformException>().having(
          (PlatformException error) => error.code,
          'code',
          'tessdata-path-invalid',
        ),
      ),
    );
  });

  test('a blank path is rejected instead of resolving to the cwd', () async {
    await expectLater(
      () => resolveTessDataDirectory('   ', language: 'eng'),
      throwsA(
        isA<PlatformException>().having(
          (PlatformException error) => error.code,
          'code',
          'tessdata-path-invalid',
        ),
      ),
    );
  });
}
