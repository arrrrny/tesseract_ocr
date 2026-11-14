import Flutter
import Foundation
#if canImport(UIKit)
import UIKit
import Vision
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(SwiftyTesseract)
import SwiftyTesseract
import libtesseract
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
        let tessData = args["tessData"] as? String
        let rawConfig = (args["config"] as? [String: Any]) ?? args

        #if canImport(UIKit) && canImport(SwiftyTesseract) && !os(macOS)
        let selectedEngine = OCREngineConfig.shared.configure(fromParams: rawConfig)
        switch selectedEngine {
        case .appleVision:
            performVisionOCR(
                imagePath: imagePath,
                language: language,
                result: result
            )
        case .swiftyTesseract:
            performTesseractOCR(
                imagePath: imagePath,
                language: language,
                tessData: tessData,
                config: rawConfig,
                result: result
            )
        }
        #elseif canImport(SwiftyTesseract)
        performTesseractOCR(
            imagePath: imagePath,
            language: language,
            tessData: tessData,
            config: rawConfig,
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

    #if canImport(UIKit) && canImport(SwiftyTesseract) && !os(macOS)
    private func performVisionOCR(
        imagePath: String,
        language: String,
        result: @escaping FlutterResult
    ) {
        guard let image = UIImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage else {
            result(FlutterError(
                code: "IMAGE_LOAD_FAILED",
                message: "Could not load image at path: \(imagePath)",
                details: nil
            ))
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest { [weak self] (request, error) in
            guard let self = self else { return }
            if let error = error {
                result(FlutterError(
                    code: "OCR_ERROR",
                    message: "Vision OCR failed: \(error.localizedDescription)",
                    details: nil
                ))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                result(FlutterError(
                    code: "OCR_NO_RESULTS",
                    message: "No text observations found",
                    details: nil
                ))
                return
            }

            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            let text = recognizedStrings.joined(separator: "\n")
            result(text)
        }

        request.recognitionLevel = .accurate
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = ["en-US"]
            if language.lowercased().contains("fra") {
                request.recognitionLanguages = ["fr-FR"]
            } else if language.lowercased().contains("deu") {
                request.recognitionLanguages = ["de-DE"]
            } else if language.lowercased().contains("spa") {
                request.recognitionLanguages = ["es-ES"]
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_PROCESS_ERROR",
                        message: "Failed to perform Vision OCR: \(error.localizedDescription)",
                        details: nil
                    ))
                }
            }
        }
    }
    #endif

    #if canImport(SwiftyTesseract)
    private func validateTessData(
        language: String,
        tessData: String?,
        fileManager: FileManager = .default
    ) -> (directoryPath: String, trainedDataFiles: [String])? {
        let languageParts = language
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !languageParts.isEmpty else { return nil }

        var candidates: [String] = []
        if let tessData = tessData?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tessData.isEmpty {
            candidates.append(tessData)
            candidates.append((tessData as NSString).appendingPathComponent("tessdata"))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append((resourceURL as NSURL).appendingPathComponent("tessdata")?.path ?? "")
            candidates.append((resourceURL as NSURL).appendingPathComponent("flutter_assets/assets/tessdata")?.path ?? "")
        }
        candidates.append((Bundle.main.bundleURL as NSURL).appendingPathComponent("tessdata")?.path ?? "")
        candidates.append((Bundle.main.bundleURL as NSURL).appendingPathComponent("flutter_assets/assets/tessdata")?.path ?? "")

        for candidate in candidates where !candidate.isEmpty {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            var foundFiles: [String] = []
            var allPresent = true
            for part in languageParts {
                let fileName = "\(part).traineddata"
                let filePath = (candidate as NSString).appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: filePath) {
                    foundFiles.append(fileName)
                } else {
                    allPresent = false
                    break
                }
            }

            if allPresent {
                return (candidate, foundFiles)
            }
        }

        return nil
    }

    private func performTesseractOCR(
        imagePath: String,
        language: String,
        tessData: String?,
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

        // Preflight tessdata directory and traineddata files so we never hit
        // SwiftyTesseract's fatalError on physical devices.
        guard let validatedTessData = validateTessData(language: language, tessData: tessData) else {
            let languageParts = language
                .split(separator: "+")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let basePathDescription = (tessData?.isEmpty == false) ? tessData! : "Bundle.main/tessdata"
            let missingFiles = languageParts
                .map { "\($0).traineddata" }
                .joined(separator: ", ")
            result(FlutterError(
                code: "TESSDATA_NOT_FOUND",
                message: "Missing or unreadable traineddata file(s) [\(missingFiles)] in tessdata directory at '\(basePathDescription)'. Ensure .traineddata files are listed in assets/tessdata_config.json and bundled in assets/tessdata/.",
                details: nil
            ))
            return
        }

        // Configure Tesseract
        let languageCodes = language.split(separator: "+").map { String($0) }

        // Determine engine mode
        let engineMode: EngineMode
        if let engineStr = config?["engine"] as? String {
            switch engineStr.lowercased() {
            case "tesseract":
                engineMode = .tesseractOnly
            case "vision":
                #if canImport(UIKit) && !os(macOS)
                engineMode = .lstmOnly
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

        // Create Tesseract instance against the validated tessdata path via TessBaseAPI
        guard let tessBaseAPI = TessBaseAPICreate() else {
            result(FlutterError(
                code: "OCR_INIT_FAILED",
                message: "Failed to create Tesseract API instance.",
                details: nil
            ))
            return
        }
        defer {
            TessBaseAPIEnd(tessBaseAPI)
            TessBaseAPIDelete(tessBaseAPI)
        }

        let initReturnCode = TessBaseAPIInit2(
            tessBaseAPI,
            validatedTessData.directoryPath,
            language,
            engineMode
        )
        guard initReturnCode == 0 else {
            result(FlutterError(
                code: "OCR_INIT_FAILED",
                message: "Failed to initialize Tesseract with language '\(language)' at '\(validatedTessData.directoryPath)' (code: \(initReturnCode)). Ensure \(validatedTessData.trainedDataFiles.joined(separator: ", ")) matches the selected engine mode.",
                details: nil
            ))
            return
        }

        if let options = config?["options"] as? [String: Any] {
            for (key, value) in options {
                let strValue: String
                if let s = value as? String {
                    strValue = s
                } else if let b = value as? Bool {
                    strValue = b ? "1" : "0"
                } else if let n = value as? NSNumber {
                    strValue = n.stringValue
                } else {
                    strValue = "\(value)"
                }
                TessBaseAPISetVariable(tessBaseAPI, key, strValue)
            }
        }

        // Perform OCR on a serial queue to prevent race conditions
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

            // Set up timeout
            let timeoutWorkItem = DispatchWorkItem {
                completeOnce(FlutterError(
                    code: "OCR_TIMEOUT",
                    message: "OCR operation timed out after 30 seconds",
                    details: nil
                ))
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: timeoutWorkItem)

            // Perform OCR
            guard let pix = pixReadMem([UInt8](imageData).withUnsafeBytes { $0.baseAddress }, imageData.count) else {
                timeoutWorkItem.cancel()
                completeOnce(FlutterError(
                    code: "OCR_PROCESS_ERROR",
                    message: "Failed to decode image data for OCR.",
                    details: nil
                ))
                return
            }
            defer {
                pixDestroy(pix)
            }

            TessBaseAPISetImage2(tessBaseAPI, pix)
            if TessBaseAPIGetSourceYResolution(tessBaseAPI) < 70 {
                TessBaseAPISetSourceResolution(tessBaseAPI, 300)
            }

            let recognized = TessBaseAPIRecognize(tessBaseAPI, nil) == 0
            timeoutWorkItem.cancel()

            guard recognized, let textPtr = TessBaseAPIGetUTF8Text(tessBaseAPI) else {
                completeOnce(FlutterError(
                    code: "OCR_PROCESS_ERROR",
                    message: "Tesseract OCR failed to extract text from image.",
                    details: nil
                ))
                return
            }
            defer {
                TessDeleteText(textPtr)
            }

            let recognizedText = String(cString: textPtr)
            completeOnce(recognizedText)
        }
    }
    #endif
}