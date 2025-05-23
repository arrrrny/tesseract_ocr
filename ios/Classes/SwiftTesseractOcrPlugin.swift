import Flutter
import UIKit
import Vision

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
            
            // Set recognition level
            request.recognitionLevel = .accurate
            
            // Set language correction to not use it
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