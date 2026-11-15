#include "tesseract_ocr/tesseract_ocr_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <tesseract/baseapi.h>
#include <tesseract/capi.h>
#include <leptonica/allheaders.h>

#include <cerrno>
#include <cstring>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

namespace {

constexpr char kChannelName[] = "tesseract_ocr";

// Traineddata install locations probed in order. Tesseract's own default path
// is compiled in and is wrong on most distros, so one is resolved explicitly.
const char* kTessdataCandidates[] = {
    "/usr/share/tesseract-ocr/4.00/tessdata",
    "/usr/share/tesseract-ocr/5.00/tessdata",
    "/usr/share/tesseract-ocr/tessdata",
    "/usr/share/tessdata",
    "/usr/local/share/tessdata",
};

// A path is safe to hand to the engine only if it carries no shell
// metacharacters. The plugin spawns no shell, but a hostile path could still
// confuse an argument parser downstream.
bool path_is_safe(const std::string& path) {
  return path.find_first_of(";|&$`\n\r") == std::string::npos;
}

// True when `dir` directly contains a traineddata file for every component of
// `language`, which may be `+`-separated (e.g. "eng+fra").
bool dir_has_language(const std::string& dir, const std::string& language) {
  if (language.empty()) return false;
  size_t start = 0;
  while (true) {
    size_t plus = language.find('+', start);
    const std::string part = language.substr(
        start, plus == std::string::npos ? std::string::npos : plus - start);
    if (part.empty()) return false;
    const std::string file = dir + "/" + part + ".traineddata";
    if (!g_file_test(file.c_str(), G_FILE_TEST_EXISTS)) return false;
    if (plus == std::string::npos) break;
    start = plus + 1;
  }
  return true;
}

// Resolves the tessdata directory to hand to TessBaseAPIInit3. A caller-supplied
// path may point either directly at the traineddata files or at a parent that
// holds a `tessdata/` subdir (the Dart layer copies assets there), so both are
// checked before falling back to the well-known system locations. Returns ""
// when no traineddata is found, letting the engine use its compiled-in default.
std::string resolve_tessdata(const std::string& tess_data_path,
                             const std::string& language) {
  if (!tess_data_path.empty()) {
    if (dir_has_language(tess_data_path, language)) return tess_data_path;
    const std::string nested = tess_data_path + "/tessdata";
    if (dir_has_language(nested, language)) return nested;
  }
  for (const char* candidate : kTessdataCandidates) {
    if (dir_has_language(candidate, language)) return candidate;
  }
  return "";
}

// Writes the image bytes a call carried to a unique temporary file and returns
// its path, or "" when the write failed.
//
// Leptonica's `pixReadMem` is the natural entry point for bytes, but its
// signature has changed across the versions a distro may ship, and the plugin
// is built against the system's leptonica rather than a pinned one. A file
// keeps the decode path on the one signature this plugin already compiles.
std::string write_bytes_to_temp_file(const uint8_t* data, size_t length) {
  if (data == nullptr || length == 0) return "";

  // Honour $TMPDIR — sandboxed Flutter runtimes (flatpak and friends) set it
  // to a directory the app is allowed to write — and fall back to /tmp when
  // it is unset or empty.
  const char* tmp_dir = getenv("TMPDIR");
  const char* base_dir =
      (tmp_dir != nullptr && tmp_dir[0] != '\0') ? tmp_dir : "/tmp";
  std::string template_string =
      std::string(base_dir) + "/tesseract_ocr_XXXXXX";
  std::vector<char> path_template(template_string.begin(),
                                  template_string.end());
  path_template.push_back('\0');
  const int fd = mkstemp(path_template.data());
  if (fd < 0) return "";

  std::string path(path_template.data());
  size_t written = 0;
  while (written < length) {
    const ssize_t chunk =
        write(fd, data + written, length - written);
    if (chunk < 0 && errno == EINTR) {
      // A signal landed mid-write: the bytes are not lost, retry.
      continue;
    }
    if (chunk <= 0) {
      close(fd);
      unlink(path.c_str());
      return "";
    }
    written += static_cast<size_t>(chunk);
  }

  close(fd);
  return path;
}

std::string string_arg(FlValue* args, const char* key,
                       const std::string& fallback) {
  FlValue* field = fl_value_lookup_string(args, key);
  if (field == nullptr || fl_value_get_type(field) != FL_VALUE_TYPE_STRING) {
    return fallback;
  }
  const char* raw = fl_value_get_string(field);
  return raw == nullptr ? fallback : std::string(raw);
}

// Flattens the `options` map into tesseract variable assignments, skipping the
// keys the engine owns.
std::vector<std::pair<std::string, std::string>> collect_options(
    FlValue* args) {
  std::vector<std::pair<std::string, std::string>> collected;
  FlValue* options = fl_value_lookup_string(args, "options");
  if (options == nullptr || fl_value_get_type(options) != FL_VALUE_TYPE_MAP) {
    return collected;
  }
  const size_t count = fl_value_get_length(options);
  for (size_t i = 0; i < count; i++) {
    FlValue* key = fl_value_get_map_key(options, i);
    FlValue* value = fl_value_get_map_value(options, i);
    if (key == nullptr || value == nullptr) continue;
    if (fl_value_get_type(key) != FL_VALUE_TYPE_STRING) continue;

    const char* raw_key = fl_value_get_string(key);
    if (raw_key == nullptr) continue;
    const std::string name(raw_key);
    if (name == "language" || name == "engine" || name == "tessDataPath") {
      continue;
    }

    switch (fl_value_get_type(value)) {
      case FL_VALUE_TYPE_STRING:
        collected.emplace_back(name, fl_value_get_string(value));
        break;
      case FL_VALUE_TYPE_INT:
        collected.emplace_back(name, std::to_string(fl_value_get_int(value)));
        break;
      case FL_VALUE_TYPE_BOOL:
        collected.emplace_back(name, fl_value_get_bool(value) ? "1" : "0");
        break;
      default:
        break;
    }
  }
  return collected;
}

struct Recognition {
  std::string text;
  std::string error_code;
  std::string error_message;
};

// Runs the engine. Blocking and CPU-bound, so it is called from a worker
// thread — never from the main loop.
Recognition recognize(const std::string& image_path,
                      const std::string& language,
                      const std::string& tess_data_path,
                      const std::vector<std::pair<std::string, std::string>>&
                          options,
                      bool hocr) {
  Recognition out;

  TessBaseAPI* api = TessBaseAPICreate();
  if (api == nullptr) {
    out.error_code = "OCR_INIT_FAILED";
    out.error_message = "Failed to create the Tesseract API instance.";
    return out;
  }

  std::string tessdata = resolve_tessdata(tess_data_path, language);

  // A NULL datapath falls back to a compiled-in default most distros do not
  // honour, so one is only passed when it was actually resolved.
  if (TessBaseAPIInit3(api, tessdata.empty() ? nullptr : tessdata.c_str(),
                       language.c_str()) != 0) {
    TessBaseAPIDelete(api);
    out.error_code = "TESSDATA_NOT_FOUND";
    out.error_message =
        "Could not initialize Tesseract for language '" + language +
        "'. Install its traineddata (e.g. apt install tesseract-ocr-eng) or "
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

  char* raw = hocr ? TessBaseAPIGetHOCRText(api, 0)
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

struct OsdResult {
  bool ok = false;
  int orientation = 0;
  double orientation_conf = 0.0;
  std::string script;
  double script_conf = 0.0;
  std::string error_code;
  std::string error_message;
};

// Runs orientation & script detection. Blocking and CPU-bound, so it is called
// from a worker thread — never from the main loop.
OsdResult detect_osd(const std::string& image_path,
                     const std::string& language,
                     const std::string& tess_data_path,
                     const std::vector<std::pair<std::string, std::string>>&
                         options) {
  OsdResult out;

#if defined(DISABLED_LEGACY_ENGINE)
  out.error_code = "OSD_UNAVAILABLE";
  out.error_message =
      "Orientation & script detection is not available in this Tesseract "
      "build (legacy engine disabled).";
  return out;
#else
  TessBaseAPI* api = TessBaseAPICreate();
  if (api == nullptr) {
    out.error_code = "OCR_INIT_FAILED";
    out.error_message = "Failed to create the Tesseract API instance.";
    return out;
  }

  std::string tessdata = resolve_tessdata(tess_data_path, language);
  if (TessBaseAPIInit3(api, tessdata.empty() ? nullptr : tessdata.c_str(),
                       language.c_str()) != 0) {
    TessBaseAPIDelete(api);
    out.error_code = "TESSDATA_NOT_FOUND";
    out.error_message =
        "Could not initialize Tesseract for language '" + language +
        "'. Install a legacy-capable traineddata (e.g. osd.traineddata) or "
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

  int orient_deg = 0;
  float orient_conf = 0.0f;
  float script_conf = 0.0f;
  const char* script_name = nullptr;
  BOOL detected = TessBaseAPIDetectOrientationScript(
      api, &orient_deg, &orient_conf, &script_name, &script_conf);

  if (detected) {
    out.ok = true;
    out.orientation = orient_deg;
    out.orientation_conf = orient_conf;
    out.script = script_name == nullptr ? "" : script_name;
    out.script_conf = script_conf;
  } else {
    out.error_code = "OSD_FAILED";
    out.error_message =
        "Tesseract could not detect orientation & script. Ensure a "
        "legacy-capable traineddata (e.g. osd.traineddata) is bundled.";
  }

  if (script_name != nullptr) {
    TessDeleteText(script_name);
  }
  pixDestroy(&pix);
  TessBaseAPIDelete(api);
  return out;
#endif
}

// Schedules an OSD reply for `call` on the main loop and releases it after.
// `value` is a floating FlValue reference (or null for an error); ownership is
// taken. `call` is a reference the caller already took.
void respond_osd_on_main(FlMethodCall* call, FlValue* value,
                         const std::string& code, const std::string& message) {
  struct Reply {
    FlMethodCall* call;
    FlValue* value;
    std::string code;
    std::string message;
  };
  auto* payload = new Reply{call, value, code, message};

  auto respond = +[](gpointer data) -> gboolean {
    auto* r = static_cast<Reply*>(data);
    if (r->value != nullptr) {
      fl_method_call_respond_success(r->call, r->value, nullptr);
      fl_value_unref(r->value);
    } else {
      fl_method_call_respond_error(r->call, r->code.c_str(), r->message.c_str(),
                                   nullptr, nullptr);
    }
    g_object_unref(r->call);
    delete r;
    return G_SOURCE_REMOVE;
  };

  g_main_context_invoke_full(g_main_context_default(), G_PRIORITY_DEFAULT,
                             respond, payload, nullptr);
}

void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                    gpointer /*user_data*/) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (method == nullptr) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }

  if (g_strcmp0(method, "isSupported") == 0) {
    // A bare bool, matching the other platforms; the Dart layer never wraps it.
    fl_method_call_respond_success(method_call, fl_value_new_bool(true),
                                   nullptr);
    return;
  }

  if (g_strcmp0(method, "detectOrientationScript") == 0) {
    const std::string image_path = string_arg(args, "imagePath", "");
    if (image_path.empty()) {
      fl_method_call_respond_error(method_call, "MISSING_PARAMS",
                                   "Required parameter 'imagePath' is missing.",
                                   nullptr, nullptr);
      return;
    }

    if (string_arg(args, "engine", "defaultEngine") == "vision") {
      fl_method_call_respond_error(
          method_call, "UNSUPPORTED_ENGINE",
          "Apple Vision is iOS-only and has no OSD; use OCREngine.tesseract.",
          nullptr, nullptr);
      return;
    }

    if (!path_is_safe(image_path)) {
      fl_method_call_respond_error(method_call, "INVALID_PATH",
                                   "Image path contains invalid characters.",
                                   nullptr, nullptr);
      return;
    }

    FlMethodCall* retained_call = FL_METHOD_CALL(g_object_ref(method_call));
    const std::string language = string_arg(args, "language", "eng");
    const std::string tess_data = string_arg(args, "tessData", "");
    const auto options = collect_options(args);

    std::thread([retained_call, image_path, language, tess_data, options]() {
      OsdResult osd = detect_osd(image_path, language, tess_data, options);

      FlValue* reply = nullptr;
      std::string code;
      std::string message;
      if (osd.ok) {
        reply = fl_value_new_map();
        fl_value_set_string_take(
            reply, "orientation", fl_value_new_int(osd.orientation));
        fl_value_set_string_take(
            reply, "orientation_conf", fl_value_new_float(osd.orientation_conf));
        fl_value_set_string_take(reply, "script",
                                 fl_value_new_string(osd.script.c_str()));
        fl_value_set_string_take(reply, "script_conf",
                                 fl_value_new_float(osd.script_conf));
      } else {
        code = osd.error_code;
        message = osd.error_message;
      }

      respond_osd_on_main(retained_call, reply, code, message);
    }).detach();
    return;
  }

  if (g_strcmp0(method, "extractText") != 0 &&
      g_strcmp0(method, "extractHocr") != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }

  const std::string image_path = string_arg(args, "imagePath", "");

  // A call carries either a path or the encoded image. Bytes never become a
  // path in the reply: they are written to a temporary file on the worker
  // thread, so the argument this handler answers for stays the caller's own.
  FlValue* raw_image_bytes = fl_value_lookup_string(args, "imageBytes");
  const bool has_image_bytes =
      raw_image_bytes != nullptr &&
      fl_value_get_type(raw_image_bytes) == FL_VALUE_TYPE_UINT8_LIST &&
      fl_value_get_length(raw_image_bytes) > 0;

  if (!has_image_bytes && image_path.empty()) {
    fl_method_call_respond_error(method_call, "MISSING_PARAMS",
                                 "Required parameter 'imagePath' is missing.",
                                 nullptr, nullptr);
    return;
  }

  if (string_arg(args, "engine", "defaultEngine") == "vision") {
    fl_method_call_respond_error(
        method_call, "UNSUPPORTED_ENGINE",
        "Apple Vision is iOS-only; use OCREngine.tesseract on Linux.", nullptr,
        nullptr);
    return;
  }

  if (!has_image_bytes && !path_is_safe(image_path)) {
    fl_method_call_respond_error(method_call, "INVALID_PATH",
                                 "Image path contains invalid characters.",
                                 nullptr, nullptr);
    return;
  }

  std::vector<uint8_t> image_bytes;
  if (has_image_bytes) {
    const uint8_t* raw = fl_value_get_uint8_list(raw_image_bytes);
    image_bytes.assign(raw, raw + fl_value_get_length(raw_image_bytes));
  }

  // Take a reference on `method_call` synchronously, before the worker thread
  // starts. The Flutter engine drops its own reference as soon as
  // `method_call_cb` returns, so a ref taken later (inside the thread) would
  // race with that drop and risk a use-after-free.
  FlMethodCall* retained_call = FL_METHOD_CALL(g_object_ref(method_call));

  const std::string language = string_arg(args, "language", "eng");
  const std::string tess_data = string_arg(args, "tessData", "");
  const auto options = collect_options(args);

  // The engine is blocking and can run for seconds, so it moves to a worker
  // thread. The reply is marshalled back through the main loop.
  const bool hocr = g_strcmp0(method, "extractHocr") == 0;
  std::thread([retained_call, image_path, language, tess_data, options, hocr,
               image_bytes]() {
    Recognition outcome;
    if (image_bytes.empty()) {
      outcome = recognize(image_path, language, tess_data, options, hocr);
    } else {
      // The engine reads the image from disk, so the bytes are written to a
      // unique temporary file for the duration of this recognition and removed
      // again — the plugin never leaves an image behind.
      const std::string temporary =
          write_bytes_to_temp_file(image_bytes.data(), image_bytes.size());
      if (temporary.empty()) {
        outcome.error_code = "IMAGE_LOAD_FAILED";
        outcome.error_message =
            "Could not write the image bytes to a temporary file.";
      } else {
        outcome = recognize(temporary, language, tess_data, options, hocr);
        unlink(temporary.c_str());
      }
    }

    // A failure is reported the same way the other platforms report it: a
    // method-channel error, which the Dart side surfaces as a
    // PlatformException carrying this code.
    g_autoptr(FlValue) reply = nullptr;
    std::string code;
    std::string message;
    if (outcome.error_code.empty()) {
      // The Dart layer invokes `extractText` with `invokeMethod<String>`, so the
      // success payload must be the recognized text as a bare string — a
      // wrapper map would fail the cast and surface as an empty result.
      reply = fl_value_new_string(outcome.text.c_str());
    } else {
      code = outcome.error_code;
      message = outcome.error_message;
    }

    struct Reply {
      FlMethodCall* call;
      FlValue* value;  // null => error
      std::string* code;
      std::string* message;
    };
    // `retained_call` was referenced on the main thread before this lambda
    // began; `respond_on_main` releases it after the reply is sent.
    // FlValue is reference counted (not a GObject), so it is retained with
    // fl_value_ref rather than g_object_ref.
    auto* payload = new Reply{
        retained_call,
        reply != nullptr ? fl_value_ref(reply) : nullptr,
        code.empty() ? nullptr : new std::string(code),
        message.empty() ? nullptr : new std::string(message)};

    // GSourceFunc is gboolean (*)(gpointer). It runs on the main loop and
    // releases the references taken above once the reply has been sent.
    auto respond_on_main = +[](gpointer data) -> gboolean {
      auto* r = static_cast<Reply*>(data);
      if (r->value != nullptr) {
        fl_method_call_respond_success(r->call, r->value, nullptr);
        fl_value_unref(r->value);
      } else {
        fl_method_call_respond_error(r->call, r->code->c_str(),
                                     r->message->c_str(), nullptr, nullptr);
      }
      g_object_unref(r->call);
      delete r->code;
      delete r->message;
      delete r;
      return G_SOURCE_REMOVE;
    };

    g_main_context_invoke_full(g_main_context_default(), G_PRIORITY_DEFAULT,
                               respond_on_main, payload, nullptr);
  }).detach();
}

}  // namespace

void tesseract_ocr_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
}