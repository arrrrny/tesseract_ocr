#if os(Linux)
import Flutter
import Foundation
import TesseractOcrCpp

/// Linux-specific Tesseract OCR plugin using system library via C++ interop
public class SwiftTesseractOcrPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "tesseract_ocr",
            binaryMessenger: registrar.messenger()
        )
        let instance = SwiftTesseractOcrPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "extractText":
            handleExtractText(call: call, result: result)
        case "isSupported":
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleExtractText(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Arguments were invalid or missing",
                details: nil
            ))
            return
        }

        guard let imagePath = args["imagePath"] as? String, !imagePath.isEmpty else {
            result(FlutterError(
                code: "MISSING_IMAGE_PATH",
                message: "imagePath is required and must not be empty",
                details: nil
            ))
            return
        }

        let language = (args["language"] as? String) ?? "eng"

        let options = args["options"] as? [String: Any]
            ?? (args["config"] as? [String: Any])?["options"] as? [String: Any]

        performLinuxOCR(
            imagePath: imagePath,
            language: language,
            options: options,
            result: result
        )
    }

    private func performLinuxOCR(
        imagePath: String,
        language: String,
        options: [String: Any]?,
        result: @escaping FlutterResult
    ) {
        // Validate image path
        let invalidChars = CharacterSet(charactersIn: ";|&$`\n\r")
        if imagePath.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
            result(FlutterError(
                code: "INVALID_PATH",
                message: "Image path contains invalid characters",
                details: nil
            ))
            return
        }

        DispatchQueue(label: "com.tesseract.ocr", qos: .userInitiated).async {
            // The timeout and the OCR completion can race: without this guard
            // `result` would be called twice (once by whichever finishes first,
            // once by the other) and a second FlutterResult call crashes the app.
            let resultLock = NSLock()
            var didComplete = false
            let completeOnce: (Any?) -> Void = { value in
                resultLock.lock()
                defer { resultLock.unlock() }
                guard !didComplete else { return }
                didComplete = true
                DispatchQueue.main.async {
                    result(value)
                }
            }

            // Create Tesseract API instance
            guard let api = TessBaseAPICreate() else {
                completeOnce(FlutterError(
                    code: "OCR_INIT_FAILED",
                    message: "Failed to create Tesseract API instance",
                    details: nil
                ))
                return
            }
            defer {
                TessBaseAPIDelete(api)
            }

            // Initialize with language. `TessBaseAPIInit3` needs an explicit
            // tessdata directory on most distros — a NULL datapath falls back to
            // a compiled-in path that is frequently wrong — so probe the common
            // install locations first and only then fall back to the default.
            let fileManager = FileManager.default
            let tessdataCandidates = [
                "/usr/share/tesseract-ocr/4.00/tessdata",
                "/usr/share/tesseract-ocr/5.00/tessdata",
                "/usr/share/tesseract-ocr/tessdata",
                "/usr/share/tessdata",
                "/usr/local/share/tessdata",
            ]
            var initResult: Int32 = -1
            for path in tessdataCandidates where fileManager.fileExists(atPath: path) {
                initResult = TessBaseAPIInit3(api, path, language)
                if initResult == 0 { break }
            }
            if initResult != 0 {
                initResult = TessBaseAPIInit3(api, nil, language)
            }
            guard initResult == 0 else {
                completeOnce(FlutterError(
                    code: "OCR_INIT_FAILED",
                    message: "Failed to initialize Tesseract with language: \(language)",
                    details: nil
                ))
                return
            }
            defer {
                TessBaseAPIEnd(api)
            }

            Self.applyOptions(to: api, options: options)

            // Read image file
            guard let pix = pixRead(imagePath) else {
                completeOnce(FlutterError(
                    code: "IMAGE_LOAD_FAILED",
                    message: "Could not load image at path: \(imagePath)",
                    details: nil
                ))
                return
            }
            defer {
                pixDestroy(pix)
            }

            // Set image
            TessBaseAPISetImage2(api, pix)

            // Set up timeout
            let timeoutWorkItem = DispatchWorkItem {
                completeOnce(FlutterError(
                    code: "OCR_TIMEOUT",
                    message: "OCR operation timed out after 30 seconds",
                    details: nil
                ))
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: timeoutWorkItem)

            // Recognize text
            let success = TessBaseAPIRecognize(api, nil) == 0
            timeoutWorkItem.cancel()

            guard success else {
                completeOnce(FlutterError(
                    code: "OCR_PROCESS_ERROR",
                    message: "Tesseract OCR failed to recognize text",
                    details: nil
                ))
                return
            }

            // Get recognized text
            guard let textPtr = TessBaseAPIGetUTF8Text(api) else {
                completeOnce(FlutterError(
                    code: "OCR_NO_RESULTS",
                    message: "No text was recognized",
                    details: nil
                ))
                return
            }

            let recognizedText = String(cString: textPtr)
            TessDeleteText(textPtr)

            completeOnce(recognizedText)
        }
    }

    // MARK: - Options

    /// The key the Dart layer uses for the page segmentation mode.
    private static let pageSegModeKey = "tessedit_pageseg_mode"

    /// Keys the plugin consumes itself and must never forward as a variable.
    private static let reservedOptionKeys: Set<String> = [
        "language",
        "engine",
        "tessDataPath",
        pageSegModeKey,
    ]

    /// Applies the caller's options to a freshly initialized API.
    ///
    /// The page segmentation mode is one call and every other key is a Tesseract
    /// variable, so a caller's `tessedit_pageseg_mode` reaches the engine as a
    /// PSM instead of being dropped (issue #59).
    private static func applyOptions(
        to api: OpaquePointer?,
        options: [String: Any]?
    ) {
        guard let api = api, let options = options, !options.isEmpty else {
            return
        }

        for key in options.keys.sorted() {
            guard let value = options[key], !(value is NSNull) else { continue }
            let text = "\(value)"

            if key == pageSegModeKey {
                guard let mode = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                      mode >= 0, mode <= 13,
                      let psm = TessPageSegMode(rawValue: mode) else {
                    // An unusable mode keeps the PSM the engine initialized
                    // with; it is reported rather than silently applied.
                    print("OCR: ignoring unsupported page segmentation mode: \(text)")
                    continue
                }
                TessBaseAPISetPageSegMode(api, psm)
                continue
            }

            if reservedOptionKeys.contains(key) {
                continue
            }

            // An unknown variable is the caller's spelling, not a failed
            // recognition: the return value is deliberately ignored.
            TessBaseAPISetVariable(api, key, text)
        }
    }
}
#endif