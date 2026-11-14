import Flutter
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(SwiftyTesseract)
import SwiftyTesseract
#endif

/// Unified Tesseract OCR plugin for iOS, macOS, and Linux
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
            handleIsSupported(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleIsSupported(result: @escaping FlutterResult) {
        #if canImport(SwiftyTesseract)
        result(true)
        #else
        result(false)
        #endif
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
        let config = args["config"] as? [String: Any]

        #if canImport(SwiftyTesseract)
        performTesseractOCR(
            imagePath: imagePath,
            language: language,
            config: config,
            result: result
        )
        #else
        result(FlutterError(
            code: "NOT_SUPPORTED",
            message: "Tesseract OCR is not available on this platform",
            details: nil
        ))
        #endif
    }

    #if canImport(SwiftyTesseract)
    private func performTesseractOCR(
        imagePath: String,
        language: String,
        config: [String: Any]?,
        result: @escaping FlutterResult
    ) {
        // Validate image path contains no shell metacharacters
        let invalidChars = CharacterSet(charactersIn: ";|&$`\n\r")
        if imagePath.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
            result(FlutterError(
                code: "INVALID_PATH",
                message: "Image path contains invalid characters",
                details: nil
            ))
            return
        }

        // Load image data
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) else {
            result(FlutterError(
                code: "IMAGE_LOAD_FAILED",
                message: "Could not load image at path: \(imagePath)",
                details: nil
            ))
            return
        }

        // Configure Tesseract
        let languages = language.split(separator: "+").map { String($0) }
        let recognitionLanguages: [RecognitionLanguage]
        
        do {
            recognitionLanguages = try languages.map { lang in
                try RecognitionLanguage.fromString(lang)
            }
        } catch {
            result(FlutterError(
                code: "INVALID_LANGUAGE",
                message: "Invalid language code: \(error.localizedDescription)",
                details: nil
            ))
            return
        }

        // Determine engine mode
        let engineMode: EngineMode
        if let engineStr = config?["engine"] as? String {
            switch engineStr.lowercased() {
            case "tesseract":
                engineMode = .tesseractOnly
            case "vision":
                #if canImport(UIKit)
                engineMode = .visionOnly
                #else
                result(FlutterError(
                    code: "UNSUPPORTED_ENGINE",
                    message: "Vision engine is only supported on iOS",
                    details: nil
                ))
                return
                #endif
            default:
                engineMode = .defaultEngine
            }
        } else {
            engineMode = .lstmOnly
        }

        // Create Tesseract instance with configuration
        let tesseract = Tesseract(
            languages: recognitionLanguages,
            engineMode: engineMode
        ) { tessBaseAPI in
            // Apply additional configuration options
            if let options = config?["options"] as? [String: String] {
                for (key, value) in options {
                    if let variable = Tesseract.Variable(rawValue: key) {
                        // Parse value based on variable type
                        if let intValue = Int(value) {
                            tessellateSetVariable(tessBaseAPI, variable, .integer(intValue))
                        } else if let boolValue = Bool(value) {
                            tessellateSetVariable(tessBaseAPI, variable, .boolean(boolValue))
                        } else if let doubleValue = Double(value) {
                            tessellateSetVariable(tessBaseAPI, variable, .double(doubleValue))
                        } else {
                            tessellateSetVariable(tessBaseAPI, variable, .string(value))
                        }
                    }
                }
            }
        }

        // Perform OCR on a serial queue to prevent race conditions
        DispatchQueue(label: "com.tesseract.ocr", qos: .userInitiated).async {
            // Set up timeout
            let timeoutWorkItem = DispatchWorkItem {
                result(FlutterError(
                    code: "OCR_TIMEOUT",
                    message: "OCR operation timed out after 30 seconds",
                    details: nil
                ))
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: timeoutWorkItem)
            
            // Perform OCR
            let ocrResult = tesseract.performOCR(on: imageData)
            timeoutWorkItem.cancel()
            
            switch ocrResult {
            case .success(let recognizedText):
                DispatchQueue.main.async {
                    result(recognizedText)
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_PROCESS_ERROR",
                        message: "Tesseract OCR failed: \(error.localizedDescription)",
                        details: nil
                    ))
                }
            }
        }
    }
    
    // Helper function to set Tesseract variables
    private func tessellateSetVariable(
        _ api: TessBaseAPI,
        _ variable: Tesseract.Variable,
        _ value: TesseractValue
    ) {
        switch value {
        case .boolean(let boolValue):
            TessBaseAPISetVariable(api, variable.rawValue, boolValue ? "1" : "0")
        case .integer(let intValue):
            TessBaseAPISetVariable(api, variable.rawValue, String(intValue))
        case .double(let doubleValue):
            TessBaseAPISetVariable(api, variable.rawValue, String(doubleValue))
        case .string(let stringValue):
            TessBaseAPISetVariable(api, variable.rawValue, stringValue)
        }
    }
    
    private enum TesseractValue {
        case boolean(Bool)
        case integer(Int)
        case double(Double)
        case string(String)
    }
    #endif
}