import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tesseract_ocr/tesseract_ocr_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelTesseractOcr platform = MethodChannelTesseractOcr();
  const MethodChannel channel = MethodChannel('tesseract_ocr');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
