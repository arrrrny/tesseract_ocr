#include "tesseract_ocr_plugin.h"

// <windows.h> has to come first: it drags in the platform headers the Flutter
// wrapper and the engine headers below expect, and NOMINMAX keeps it from
// defining min/max macros that would break the standard library.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

// Tesseract's C API is C, but in C++ it pulls in the C++ API (baseapi.h), which
// in turn pulls in Leptonica's allheaders.h. Leptonica is a required link
// dependency anyway — `pixRead` is how an image file reaches the engine — so
// there is one OCR dependency, not two.
//
// The include is wrapped because the plugin target is compiled with /W4 /WX and
// a third-party header that warns would break the build.
#pragma warning(push, 0)
#include <tesseract/capi.h>
#pragma warning(pop)

#include <cstdlib>
#include <map>
#include <memory>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

namespace tesseract_ocr {
namespace {

/// Traineddata directories probed when the caller did not supply one.
///
/// The Dart layer copies the asset tessdata into the app's documents directory
/// and passes that in, so these are the fallback for a system install. Both the
/// 64-bit and the 32-bit install prefixes are checked because the installer
/// lets the user choose, and the per-user install is the one a non-admin gets.
const char* kTessdataCandidates[] = {
    "C:\\Program Files\\Tesseract-OCR\\tessdata",
    "C:\\Program Files (x86)\\Tesseract-OCR\\tessdata",
};

/// A path is safe to hand to the engine only if it carries no shell
/// metacharacters or escape characters. The plugin spawns no shell, but a
/// hostile path could still confuse a downstream argument parser, and `%` would
/// be expanded by anything that treats the string as a command line.
bool path_is_safe(const std::string& path) {
  return path.find_first_of("\"|;&$`\n\r%") == std::string::npos;
}

/// True when `path` names an existing file (not a directory).
bool file_exists(const std::string& path) {
  const DWORD attributes = GetFileAttributesA(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

/// True when `dir` directly contains a traineddata file for every component of
/// `language`, which may be `+`-separated (e.g. "eng+fra").
bool dir_has_language(const std::string& dir, const std::string& language) {
  if (language.empty()) {
    return false;
  }
  size_t start = 0;
  while (true) {
    const size_t plus = language.find('+', start);
    const std::string part = language.substr(
        start, plus == std::string::npos ? std::string::npos : plus - start);
    if (part.empty()) {
      return false;
    }
    if (!file_exists(dir + "\\" + part + ".traineddata")) {
      return false;
    }
    if (plus == std::string::npos) {
      break;
    }
    start = plus + 1;
  }
  return true;
}

/// The environment variable `TESSDATA_PREFIX`, or "" when it is unset. Tesseract
/// itself honours it, so a caller who pointed it at a custom tessdata set gets
/// that set rather than the well-known install locations.
std::string tessdata_prefix() {
  const char* value = std::getenv("TESSDATA_PREFIX");
  return value == nullptr ? std::string() : std::string(value);
}

/// Resolves the tessdata directory to hand to TessBaseAPIInit3.
///
/// A caller-supplied path may point either directly at the traineddata files or
/// at a parent that holds a `tessdata/` subdirectory — the Dart layer returns
/// the documents directory, not the tessdata directory inside it — so both are
/// checked before the system locations. Returns "" when no traineddata is found,
/// which lets the engine fall back to its own compiled-in default.
std::string resolve_tessdata(const std::string& tess_data_path,
                             const std::string& language) {
  if (!tess_data_path.empty()) {
    if (dir_has_language(tess_data_path, language)) {
      return tess_data_path;
    }
    const std::string nested = tess_data_path + "\\tessdata";
    if (dir_has_language(nested, language)) {
      return nested;
    }
  }

  const std::string prefix = tessdata_prefix();
  if (!prefix.empty() && dir_has_language(prefix, language)) {
    return prefix;
  }

  for (const char* candidate : kTessdataCandidates) {
    if (dir_has_language(candidate, language)) {
      return candidate;
    }
  }
  return "";
}

/// The string stored under `key`, or nullptr when the key is absent or does not
/// hold a string.
///
/// The map is keyed by [flutter::EncodableValue] rather than by string — that is
/// what lets a Dart map carry non-string keys at all — and its string
/// constructor is `explicit`, so the key has to be compared, not looked up. A
/// value of the wrong type reads as absent rather than being coerced: guessing a
/// path out of an int is how an argument silently changes meaning.
const std::string* string_value(const flutter::EncodableMap& args,
                                const std::string& key) {
  for (const auto& entry : args) {
    const std::string* name = std::get_if<std::string>(&entry.first);
    if (name == nullptr || *name != key) {
      continue;
    }
    return std::get_if<std::string>(&entry.second);
  }
  return nullptr;
}

/// Reads a string argument, falling back when it is absent or not a string.
std::string string_arg(const flutter::EncodableMap& args, const char* key,
                       const std::string& fallback) {
  const std::string* value = string_value(args, key);
  return value == nullptr ? fallback : *value;
}

/// Flattens the `options` map into Tesseract variable assignments, skipping the
/// keys the engine owns and the values it cannot take.
std::vector<std::pair<std::string, std::string>> collect_options(
    const flutter::EncodableMap& args) {
  std::vector<std::pair<std::string, std::string>> collected;

  const flutter::EncodableMap* options = nullptr;
  for (const auto& entry : args) {
    const std::string* name = std::get_if<std::string>(&entry.first);
    if (name == nullptr || *name != "options") {
      continue;
    }
    options = std::get_if<flutter::EncodableMap>(&entry.second);
    break;
  }
  if (options == nullptr) {
    return collected;
  }

  for (const auto& option : *options) {
    const std::string* name = std::get_if<std::string>(&option.first);
    if (name == nullptr) {
      continue;
    }
    if (*name == "language" || *name == "engine" || *name == "tessDataPath") {
      continue;
    }
    if (const std::string* text = std::get_if<std::string>(&option.second)) {
      collected.emplace_back(*name, *text);
    } else if (const bool* flag = std::get_if<bool>(&option.second)) {
      collected.emplace_back(*name, *flag ? "1" : "0");
    } else if (const int32_t* integer = std::get_if<int32_t>(&option.second)) {
      collected.emplace_back(*name, std::to_string(*integer));
    } else if (const int64_t* long_integer =
                   std::get_if<int64_t>(&option.second)) {
      collected.emplace_back(*name, std::to_string(*long_integer));
    }
  }
  return collected;
}

struct Recognition {
  std::string text;
  std::string error_code;
  std::string error_message;
};

/// Runs the engine. Blocking and CPU-bound, so it is called from a worker
/// thread — never from the platform thread.
Recognition recognize(
    const std::string& image_path, const std::string& language,
    const std::string& tess_data_path, bool is_hocr,
    const std::vector<std::pair<std::string, std::string>>& options) {
  Recognition out;

  TessBaseAPI* api = TessBaseAPICreate();
  if (api == nullptr) {
    out.error_code = "OCR_INIT_FAILED";
    out.error_message = "Failed to create the Tesseract API instance.";
    return out;
  }

  const std::string tessdata = resolve_tessdata(tess_data_path, language);

  // A NULL datapath falls back to a compiled-in default that a Windows install
  // does not provide, so one is only passed when it was actually resolved.
  if (TessBaseAPIInit3(api, tessdata.empty() ? nullptr : tessdata.c_str(),
                       language.c_str()) != 0) {
    TessBaseAPIDelete(api);
    out.error_code = "TESSDATA_NOT_FOUND";
    out.error_message =
        "Could not initialize Tesseract for language '" + language +
        "'. Install its traineddata (the UB-Mannheim installer ships eng) or "
        "pass OCRConfig(tessDataPath: ...).";
    return out;
  }

  PIX* pix = pixRead(image_path.c_str());
  if (pix == nullptr) {
    TessBaseAPIDelete(api);
    out.error_code = "IMAGE_LOAD_FAILED";
    out.error_message = "Could not read an image at '" + image_path + "'.";
    return out;
  }

  TessBaseAPISetImage2(api, pix);
  for (const auto& option : options) {
    TessBaseAPISetVariable(api, option.first.c_str(), option.second.c_str());
  }

  if (TessBaseAPIRecognize(api, nullptr) != 0) {
    pixDestroy(&pix);
    TessBaseAPIDelete(api);
    out.error_code = "OCR_PROCESS_ERROR";
    out.error_message = "Tesseract failed to recognize the image.";
    return out;
  }

  char* raw = is_hocr ? TessBaseAPIGetHOCRText(api, 0)
                      : TessBaseAPIGetUTF8Text(api);
  if (raw == nullptr) {
    pixDestroy(&pix);
    TessBaseAPIDelete(api);
    out.error_code = "OCR_NO_RESULTS";
    out.error_message = "Tesseract recognized no text.";
    return out;
  }

  out.text = raw;
  TessDeleteText(raw);
  pixDestroy(&pix);
  TessBaseAPIDelete(api);
  return out;
}

}  // namespace

// static
void TesseractOcrPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "tesseract_ocr",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<TesseractOcrPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

TesseractOcrPlugin::TesseractOcrPlugin() {}

TesseractOcrPlugin::~TesseractOcrPlugin() {}

void TesseractOcrPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "isSupported") {
    // A bare bool, matching the other platforms; the Dart layer never wraps it.
    result->Success(flutter::EncodableValue(true));
    return;
  }

  const bool is_hocr = method == "extractHocr";
  if (method != "extractText" && !is_hocr) {
    result->NotImplemented();
    return;
  }

  if (method_call.arguments() == nullptr) {
    result->Error("INVALID_ARGUMENTS", "Arguments were invalid or missing");
    return;
  }
  const flutter::EncodableMap* args =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (args == nullptr) {
    result->Error("INVALID_ARGUMENTS", "Arguments were invalid or missing");
    return;
  }

  const std::string image_path = string_arg(*args, "imagePath", "");
  if (image_path.empty()) {
    result->Error("MISSING_IMAGE_PATH",
                  "imagePath is required and must not be empty");
    return;
  }

  if (string_arg(*args, "engine", "defaultEngine") == "vision") {
    result->Error(
        "UNSUPPORTED_ENGINE",
        "Apple Vision is only available on iOS. Use OCREngine.tesseract on "
        "Windows.");
    return;
  }

  if (!path_is_safe(image_path)) {
    result->Error("INVALID_PATH", "Image path contains invalid characters.");
    return;
  }

  const std::string language = string_arg(*args, "language", "eng");
  const std::string tess_data = string_arg(*args, "tessData", "");
  const auto options = collect_options(*args);

  // Recognition moves to a worker thread: it blocks for seconds per page.
  // `result` is moved into the thread and replied to from it — the engine's
  // response send is thread-safe (the embedder API marshals the reply onto the
  // platform task runner), so no manual hop back to the platform thread is
  // needed here.
  std::thread([result = std::move(result), image_path, language, tess_data,
               is_hocr, options]() mutable {
    const Recognition outcome =
        recognize(image_path, language, tess_data, is_hocr, options);

    // A failure is reported the same way the other platforms report it: a
    // method-channel error, which the Dart side surfaces as a
    // PlatformException carrying this code.
    if (!outcome.error_code.empty()) {
      result->Error(outcome.error_code, outcome.error_message);
      return;
    }

    // The Dart layer invokes these with `invokeMethod<String>`, so the success
    // payload must be the recognized text as a bare string — a wrapper map
    // would fail the cast and surface as an empty result.
    result->Success(flutter::EncodableValue(outcome.text));
  }).detach();
}

}  // namespace tesseract_ocr