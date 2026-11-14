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
        
        performLinuxOCR(
            imagePath: imagePath,
            language: language,
            result: result
        )
    }

    private func performLinuxOCR(
        imagePath: String,
        language: String,
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
            // Create Tesseract API instance
            guard let api = TessBaseAPICreate() else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_INIT_FAILED",
                        message: "Failed to create Tesseract API instance",
                        details: nil
                    ))
                }
                return
            }
            defer {
                TessBaseAPIDelete(api)
            }

            // Initialize with language
            let initResult = TessBaseAPIInit3(api, nil, language)
            guard initResult == 0 else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_INIT_FAILED",
                        message: "Failed to initialize Tesseract with language: \(language)",
                        details: nil
                    ))
                }
                return
            }
            defer {
                TessBaseAPIEnd(api)
            }

            // Read image file
            guard let pix = pixRead(imagePath) else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "IMAGE_LOAD_FAILED",
                        message: "Could not load image at path: \(imagePath)",
                        details: nil
                    ))
                }
                return
            }
            defer {
                pixDestroy(pix)
            }

            // Set image
            TessBaseAPISetImage2(api, pix)

            // Set up timeout
            let timeoutWorkItem = DispatchWorkItem {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_TIMEOUT",
                        message: "OCR operation timed out after 30 seconds",
                        details: nil
                    ))
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: timeoutWorkItem)

            // Recognize text
            let success = TessBaseAPIRecognize(api, nil) == 0
            timeoutWorkItem.cancel()

            guard success else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_PROCESS_ERROR",
                        message: "Tesseract OCR failed to recognize text",
                        details: nil
                    ))
                }
                return
            }

            // Get recognized text
            guard let textPtr = TessBaseAPIGetUTF8Text(api) else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_NO_RESULTS",
                        message: "No text was recognized",
                        details: nil
                    ))
                }
                return
            }

            let recognizedText = String(cString: textPtr)
            TessDeleteText(textPtr)

            DispatchQueue.main.async {
                result(recognizedText)
            }
        }
    }
}
#endif