import Flutter
import UIKit
import Vision

/// The options one recognition call carried, as the Vision engine reads them.
///
/// Vision has no Tesseract variable set, so only the options with a Vision
/// counterpart survive; everything else is reported as ignored rather than
/// silently accepted (issue #59).
public struct VisionOcrOptions {
    /// The `VNRecognizeTextRequest.recognitionLevel` to use.
    public let recognitionLevel: VNRequestTextRecognitionLevel

    /// Whether Vision applies its language correction.
    public let usesLanguageCorrection: Bool

    /// The option keys that have no Vision counterpart and were dropped.
    public let ignoredKeys: [String]

    public static let `default` = VisionOcrOptions(
        recognitionLevel: .accurate,
        usesLanguageCorrection: true,
        ignoredKeys: []
    )

    /// Reads the option map the Dart layer sends.
    ///
    /// A value of the wrong type is reported as ignored instead of being coerced:
    /// the caller asked for something Vision cannot honour, and guessing a
    /// boolean from an arbitrary string is how an option silently changes meaning.
    public static func resolve(_ rawOptions: [String: Any]?) -> VisionOcrOptions {
        guard let rawOptions = rawOptions, !rawOptions.isEmpty else {
            return .default
        }

        var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
        var usesLanguageCorrection = true
        var ignoredKeys: [String] = []

        for (key in rawOptions.keys.sorted()) {
            guard let value = rawOptions[key], !(value is NSNull) else {
                ignoredKeys.append(key)
                continue
            }

            switch key {
            case "recognition_level":
                let normalized = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                switch normalized {
                case "fast":
                    recognitionLevel = .fast
                case "accurate":
                    recognitionLevel = .accurate
                default:
                    // An unknown level keeps Vision's own default, and is not
                    // silently accepted.
                    ignoredKeys.append(key)
                }
            case "uses_language_correction":
                guard let parsed = boolValue(value) else {
                    ignoredKeys.append(key)
                    continue
                }
                usesLanguageCorrection = parsed
            default:
                ignoredKeys.append(key)
            }
        }

        return VisionOcrOptions(
            recognitionLevel: recognitionLevel,
            usesLanguageCorrection: usesLanguageCorrection,
            ignoredKeys: ignoredKeys
        )
    }

    /// The boolean spellings a Dart caller may send across the channel.
    private static func boolValue(_ value: Any) -> Bool? {
        if let flag = value as? Bool {
            return flag
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        switch "\(value)".trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }
}

public class SwiftTesseractOcrPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "tesseract_ocr", binaryMessenger: registrar.messenger())
        let instance = SwiftTesseractOcrPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "extractText" {
            guard let args = call.arguments else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments were invalid", details: nil))
                return
            }
            
            guard let params = args as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments could not be parsed", details: nil))
                return
            }
            
            let languageString = (params["language"] as? String) ?? "eng"
            print("OCR: Using language: \(languageString)")

            let options = VisionOcrOptions.resolve(
                (params["config"] as? [String: Any])?["options"] as? [String: Any]
                    ?? params["options"] as? [String: Any]
            )
            if !options.ignoredKeys.isEmpty {
                // A dropped option must be visible: the Vision engine has no
                // Tesseract variable set, so silently accepting it is how a
                // caller's configuration went missing.
                print(
                    "OCR: Vision ignores unsupported option(s): "
                        + options.ignoredKeys.joined(separator: ", ")
                )
            }
            
            guard let imagePath = params["imagePath"] as? String else {
                result(FlutterError(code: "MISSING_PARAMS", message: "Required parameters missing", details: nil))
                return
            }
            
            // Debug info
            print("OCR: Using image path: \(imagePath)")
            
            guard let image = UIImage(contentsOfFile: imagePath) else {
                result(FlutterError(code: "IMAGE_LOAD_FAILED", message: "Could not load image at path: \(imagePath)", details: nil))
                return
            }
            
            guard let cgImage = image.cgImage else {
                result(FlutterError(code: "IMAGE_CONVERT_FAILED", message: "Could not convert image to CGImage", details: nil))
                return
            }
            
            // Create a new image-request handler.
            let requestHandler = VNImageRequestHandler(cgImage: cgImage)
            
            // Create a new request to recognize text.
            let request = VNRecognizeTextRequest { (request, error) in
                guard error == nil else {
                    result(FlutterError(code: "OCR_ERROR", message: "Vision OCR failed: \(error!.localizedDescription)", details: nil))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    result(FlutterError(code: "OCR_NO_RESULTS", message: "No text observations found", details: nil))
                    return
                }
                
                let recognizedStrings = observations.compactMap { observation in
                    // Return the string of the top candidate
                    observation.topCandidates(1).first?.string
                }
                
                let text = recognizedStrings.joined(separator: "\n")
                print("OCR complete, found \(observations.count) text observations")
                result(text)
            }
            
            // Recognition level, from the options the caller sent.
            request.recognitionLevel = options.recognitionLevel

            // Language correction, from the options the caller sent.
            request.usesLanguageCorrection = options.usesLanguageCorrection

            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
            } else {
                request.recognitionLanguages = ["en-US"]
                if languageString.lowercased().contains("fra") {
                    request.recognitionLanguages = ["fr-FR"]
                } else if languageString.lowercased().contains("deu") {
                    request.recognitionLanguages = ["de-DE"]
                } else if languageString.lowercased().contains("spa") {
                    request.recognitionLanguages = ["es-ES"]
                }
            }
            
            do {
                // Perform the text-recognition request.
                try requestHandler.perform([request])
            } catch {
                result(FlutterError(code: "OCR_PROCESS_ERROR", message: "Failed to perform OCR: \(error.localizedDescription)", details: nil))
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
}