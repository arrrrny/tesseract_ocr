import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'tesseract_ocr_method_channel.dart';

abstract class TesseractOcrPlatform extends PlatformInterface {
  /// Constructs a TesseractOcrPlatform.
  TesseractOcrPlatform() : super(token: _token);

  static final Object _token = Object();

  static TesseractOcrPlatform _instance = MethodChannelTesseractOcr();

  /// The default instance of [TesseractOcrPlatform] to use.
  ///
  /// Defaults to [MethodChannelTesseractOcr].
  static TesseractOcrPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [TesseractOcrPlatform] when
  /// they register themselves.
  static set instance(TesseractOcrPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
