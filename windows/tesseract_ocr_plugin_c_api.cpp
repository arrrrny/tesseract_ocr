#include "include/tesseract_ocr/tesseract_ocr_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "tesseract_ocr_plugin.h"

void TesseractOcrPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  tesseract_ocr::TesseractOcrPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}