## Unreleased

*   **OSD (orientation & script detection) API (issue #54):** `TesseractOcr.detectOrientationAndScript(imagePath, config:)` returns an `OsdResult` (page rotation, writing script, a confidence for each) mirroring `pytesseract.image_to_osd`. iOS and Linux run the native detector, Web runs tesseract.js `worker.detect()`, and Android/macOS answer an explicit `UNSUPPORTED_OSD` instead of a `MissingPluginException`
*   **OSD honours `OCRConfig.options` and a 30s watchdog on Apple:** the iOS OSD path applies the caller's Tesseract variables through the same coercion the OCR path uses, and arms the same 30s timeout — a hung decode answers `OSD_TIMEOUT` instead of parking the caller's future forever
*   **OSD language defaults to `osd` everywhere:** a call that names no language runs on the `osd` model on iOS, Linux and Web alike (the Linux handler previously fell back to `eng`, whose LSTM-only traineddata carries no legacy templates and fails detection); an explicit `OCRConfig(language:)` is honoured as given
*   **Web OSD rejects unusable image paths:** a path that is neither a bundled asset nor a direct web input (blob:, data:, http(s)://) fails with `INVALID_IMAGE_INPUT` instead of being silently fetched relative to the page URL; a non-finite confidence from any engine coerces to the defaults rather than surfacing `NaN`/`Infinity`

## 0.6.1

*   **hOCR output support (issue #53):** a new `TesseractOcr.extractHocr(imagePath, config:)` returns layout-aware hOCR (bounding boxes per word/line) alongside the plain-text `extractText`, sharing the same signature, options and validation. It is served by the Tesseract engine on Android, Web, macOS, iOS and Linux: the iOS Swift plugin and the Linux C++ plugin now honour the `extractHocr` channel method, and requesting hOCR with `OCREngine.vision` throws `UnsupportedError` (Vision produces no hOCR)
*   **`TesseractOcr.extractTextFromBytes` accepts an image in memory (issue #55):** a camera-first caller can hand over the encoded bytes instead of writing a temporary file first — the bytes go to the platform engine as they arrive (a bitmap on Android, a `Uint8Array` on Web, a data buffer on Apple platforms), and only the command-line engines (macOS, Linux) materialise them into a temporary file they delete again
*   **`OCRConfig.options` is honoured on Android again (issue #59):** `tessedit_pageseg_mode` now reaches `TessBaseAPI.setPageSegMode` instead of every recognition running with `PSM_AUTO`, and every other option is applied with `setVariable` — previously the Android plugin never read `options` at all
*   **iOS Vision honours a documented subset of options:** `recognition_level` (`fast`/`accurate`) and `uses_language_correction` are applied to the Vision request; any other key is logged as ignored rather than silently dropped
*   **macOS and Linux no longer emit the PSM and OEM twice:** both are excluded from the generic `-c key=value` passthrough, and the Linux plugin now applies the PSM and the Tesseract variables at all
*   An option a platform cannot apply is dropped and logged, never guessed: an out-of-range PSM keeps the engine default and an unparsable boolean keeps Vision's default

## 0.6.0

*   **Android native lifecycle hardening:** recognitions now run on a single daemon thread that owns the native handle and releases it in a `finally`, so a detached engine can no longer NPE or double free
*   A missing or unusable tessdata directory is reported as `INIT_ERROR` again (it was surfacing as `RECOGNITION_ERROR`)
*   The recognition intake is bounded: a caller that queues faster than OCR completes gets `BUSY` instead of unbounded pending futures
*   All native failures — `Error`s included — are answered through the method channel instead of reaching the host process

## 0.5.0

*   **BREAKING CHANGE FIX:** Fixed parameter compatibility between Dart and Android plugin that was causing "Data path must not be null!" errors
*   Improved error handling in Android plugin with clearer error messages
*   Enhanced compatibility for both direct language parameter and config-based language specification
*   Updated documentation with comprehensive troubleshooting guide
*   Removed debug print statements for cleaner logs

## 0.4.1

*   Fixed potential asset loading path duplication on certain platforms (e.g., M1) by adjusting the internal asset path constant.

## 0.4.0

*   **Added Support for Multiple OCR Engines:** Introduced `OCRConfig` to allow selecting between Apple Vision (iOS) and Tesseract engines.
*   **Added Support for SwiftyTesseract 4.0.1 (iOS via CocoaPods):** Implemented a custom CocoaPods setup with local podspecs (`SwiftyTesseract401.podspec` and `libtesseract.podspec`) to enable using SwiftyTesseract 4.0.1, which is otherwise Swift Package Manager only. Users must manually include `libtesseract.xcframework` in their iOS project. See `CUSTOM_PODS_README.md` for details.
*   Updated example app to demonstrate engine selection.
*   Added support for the latest Dart SDK.

## 0.3.0

* added language support you can pass the language as an optional parameter. TesseractOcr.extractText(imagePath, language: "financial");
if not set it will default to "eng". language must match the name of .traineddata file

## 0.2.2

* set target swift version to 4.2

## 0.2.1

* fixed swift version

## 0.2.0

* fixed dependecies

## 0.1.3

* updated swift version to 4.2

## 0.1.2+3

* added LICENSE

## 0.1.2+2

* fixed description

## 0.1.2+1

* fixed typo

## 0.1.2

* added description

## 0.1.1

* fixed path references

## 0.1.0

* Extract Text from images, Especially helpful when you are extracting single character images.
