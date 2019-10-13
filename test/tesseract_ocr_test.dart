import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  const MethodChannel channel = MethodChannel('tesseract_ocr');

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '1';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  // test('extract 1', () async {
  //   assert(await File('images/test_1.jpg').exists(), true);
  //   expect(await TesseractOcr.extractText('images/test_1.jpg'), '1');
  // });
}
