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

#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <map>
#include <memory>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

namespace tesseract_ocr {
namespace {

/// A path is safe to hand to the engine only if it carries no shell
/// metacharacters or escape characters. The plugin spawns no shell and builds
/// no command line — the path goes straight to `pixRead` — so this is the same
/// set the Linux sibling checks; `%` is a legal Windows filename character and
/// nothing on this call path would expand it, so it is not rejected.
bool path_is_safe(const std::string& path) {
  return path.find_first_of("\"|;&$`\n\r") == std::string::npos;
}

/// True when `path` names an existing file (not a directory).
///
/// The path arrives as UTF-8 bytes (the standard codec decodes the Dart string
/// verbatim), so the lookup must decode them as UTF-8: `GetFileAttributesA`
/// would read them through the process's ANSI code page and report a directory
/// like `C:\Users\Şafak\…` as missing.
bool file_exists(const std::string& path) {
  const int wide_length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, path.c_str(),
      static_cast<int>(path.size()), nullptr, 0);
  if (wide_length <= 0) {
    return false;
  }
  std::vector<wchar_t> wide(static_cast<size_t>(wide_length));
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.c_str(),
                          static_cast<int>(path.size()), wide.data(),
                          wide_length) <= 0) {
    return false;
  }
  const std::wstring wide_path(wide.data(), static_cast<size_t>(wide_length));
  const DWORD attributes = GetFileAttributesW(wide_path.c_str());
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

/// The traineddata directories probed when the caller did not supply one.
///
/// The Dart layer copies the asset tessdata into the app's documents directory
/// and passes that in, so these are the fallback for a system install. The
/// prefixes are read from the environment at run time so the list matches what
/// windows/CMakeLists.txt probes for the import libraries: both program-files
/// installs (64-bit and 32-bit) and the per-user install — the one a non-admin
/// gets — instead of hardcoded `C:\Program Files` paths that break on any
/// other system drive.
std::vector<std::string> tessdata_candidates() {
  std::vector<std::string> candidates;
  const auto add = [&candidates](const char* base_env,
                                 const char* subdirectory) {
    const char* base = std::getenv(base_env);
    if (base != nullptr && base[0] != '\0') {
      candidates.push_back(std::string(base) + "\\" + subdirectory +
                           "\\tessdata");
    }
  };
  add("ProgramFiles", "Tesseract-OCR");
  add("ProgramW6432", "Tesseract-OCR");
  add("LOCALAPPDATA", "Programs\\Tesseract-OCR");
  add("ProgramFiles(x86)", "Tesseract-OCR");
  return candidates;
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

  for (const std::string& candidate : tessdata_candidates()) {
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

/// The bytes stored under `key`, or empty when the key is absent or does not
/// hold a byte list. A Dart `Uint8List` decodes through the standard codec as
/// `std::vector<uint8_t>` — exactly one of `imagePath` and `imageBytes` is
/// set on a call (see `TesseractOcr._recognize`).
std::vector<uint8_t> bytes_arg(const flutter::EncodableMap& args,
                               const char* key) {
  for (const auto& entry : args) {
    const std::string* name = std::get_if<std::string>(&entry.first);
    if (name == nullptr || *name != key) {
      continue;
    }
    if (const std::vector<uint8_t>* bytes =
            std::get_if<std::vector<uint8_t>>(&entry.second)) {
      return *bytes;
    }
    return {};
  }
  return {};
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

/// Writes the image bytes a call carried to a unique temporary file and
/// returns its path, or "" when the write failed.
///
/// Leptonica's `pixReadMem` is the natural entry point for bytes, but its
/// signature has changed across the versions a Windows install may ship, and
/// the plugin is built against the system's leptonica rather than a pinned
/// one. A file keeps the decode path on the one signature this plugin already
/// compiles — the same shape the Linux plugin uses (`write_bytes_to_temp_file`).
std::string write_bytes_to_temp_file(const uint8_t* data, size_t length) {
  if (data == nullptr || length == 0) {
    return "";
  }

  // GetTempPath honours TMP/TEMP and falls back to the Windows directory when
  // both are unset — the Windows shape of the Linux plugin's $TMPDIR handling.
  char temp_dir[MAX_PATH];
  const DWORD dir_length = GetTempPathA(MAX_PATH, temp_dir);
  if (dir_length == 0 || dir_length >= MAX_PATH) {
    return "";
  }

  // GetTempFileName creates the file and fills `path_buffer` with its unique
  // name; a unique parameter of 0 lets it pick the suffix itself, which is the
  // mkstemp equivalent. The prefix is truncated to its first three characters.
  char path_buffer[MAX_PATH];
  if (GetTempFileNameA(temp_dir, "tesseract_ocr", 0, path_buffer) == 0) {
    return "";
  }
  const std::string path(path_buffer);

  std::ofstream file(path, std::ios::binary | std::ios::trunc);
  if (!file) {
    DeleteFileA(path.c_str());
    return "";
  }
  file.write(reinterpret_cast<const char*>(data),
             static_cast<std::streamsize>(length));
  file.close();
  if (file.fail()) {
    DeleteFileA(path.c_str());
    return "";
  }
  return path;
}

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

  // A call carries either a path or the encoded image (extractTextFromBytes).
  // Bytes never become a path in the reply: they are written to a temporary
  // file on the worker thread, so the argument this handler answers for stays
  // the caller's own.
  const std::vector<uint8_t> image_bytes = bytes_arg(*args, "imageBytes");
  const bool has_image_bytes = !image_bytes.empty();
  const std::string image_path = string_arg(*args, "imagePath", "");

  if (!has_image_bytes && image_path.empty()) {
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

  if (!has_image_bytes && !path_is_safe(image_path)) {
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
               is_hocr, options, image_bytes]() mutable {
    Recognition outcome;
    if (image_bytes.empty()) {
      outcome = recognize(image_path, language, tess_data, is_hocr, options);
    } else {
      // The engine reads the image from disk, so the bytes are written to a
      // unique temporary file for the duration of this recognition and
      // removed again — the plugin never leaves an image behind.
      const std::string temporary =
          write_bytes_to_temp_file(image_bytes.data(), image_bytes.size());
      if (temporary.empty()) {
        outcome.error_code = "IMAGE_LOAD_FAILED";
        outcome.error_message =
            "Could not write the image bytes to a temporary file.";
      } else {
        outcome = recognize(temporary, language, tess_data, is_hocr, options);
        DeleteFileA(temporary.c_str());
      }
    }

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