#ifndef FLUTTER_PLUGIN_TESSERACT_OCR_PLUGIN_H_
#define FLUTTER_PLUGIN_TESSERACT_OCR_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace tesseract_ocr {

/// The plugin's Windows implementation of the `tesseract_ocr` method channel.
///
/// Recognition runs on a worker thread: Tesseract blocks for seconds on a page,
/// which on the platform thread would freeze the app's UI.
class TesseractOcrPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  TesseractOcrPlugin();

  virtual ~TesseractOcrPlugin();

  // Disallow copy and assign.
  TesseractOcrPlugin(const TesseractOcrPlugin&) = delete;
  TesseractOcrPlugin& operator=(const TesseractOcrPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace tesseract_ocr

#endif  // FLUTTER_PLUGIN_TESSERACT_OCR_PLUGIN_H_