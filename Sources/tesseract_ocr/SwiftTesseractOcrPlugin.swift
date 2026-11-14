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
#endif

/// Unified Tesseract OCR plugin for iOS and macOS.
///
/// Two engines are reachable through one method channel:
///
/// - **Apple Vision** (`engine == "vision"`, iOS only) runs natively through
///   the Vision framework. SwiftyTesseract is a Tesseract wrapper and has no
///   Vision mode, so this path does not go through it.
/// - **Tesseract** (`engine == "tesseract"`) and the platform default run
///   through SwiftyTesseract.
///
/// The `engine` argument arrives at the TOP LEVEL of the method-call
/// arguments, which is where the Dart layer puts it; a nested `config` map is
/// accepted as a fallback for older callers.
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

        // Top level is the documented location; the nested map is a fallback
        // for callers written against the pre-SPM plugin.
        let config = args["config"] as? [String: Any]
        let engine = (args["engine"] as? String) ?? (config?["engine"] as? String)
        let language = (args["language"] as? String) ?? "eng"

        switch engine?.lowercased() {
        case "vision":
            #if canImport(UIKit)
            performVisionOCR(imagePath: imagePath, language: language, result: result)
            #else
            result(FlutterError(
                code: "UNSUPPORTED_ENGINE",
                message: "Apple Vision is only supported on iOS. "
                    + "Use OCREngine.tesseract or OCREngine.defaultEngine on macOS.",
                details: nil
            ))
            #endif
        case "tesseract", "lstm":
            #if canImport(SwiftyTesseract)
            performTesseractOCR(
                imagePath: imagePath,
                language: language,
                engineMode: (engine?.lowercased() == "lstm") ? .lstmOnly : .tesseractOnly,
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
        default:
            // `defaultEngine` and any absent engine: the platform default.
            #if canImport(UIKit)
            performVisionOCR(imagePath: imagePath, language: language, result: result)
            #elseif canImport(SwiftyTesseract)
            performTesseractOCR(
                imagePath: imagePath,
                language: language,
                engineMode: .default,
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
    }

    // MARK: - Apple Vision (iOS)

    #if canImport(UIKit)
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

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = Self.visionLanguages(for: language)
        }

        // Vision is blocking and CPU-bound: keep it off the main thread.
        DispatchQueue(label: "com.tesseract.vision", qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_PROCESS_ERROR",
                        message: "Apple Vision OCR failed: \(error.localizedDescription)",
                        details: nil
                    ))
                }
                return
            }

            let observations = request.results ?? []
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")

            DispatchQueue.main.async {
                result(text)
            }
        }
    }

    /// Maps a Tesseract language code onto a Vision recognition language.
    private static func visionLanguages(for language: String) -> [String] {
        let code = language.lowercased()
        if code.contains("fra") { return ["fr-FR"] }
        if code.contains("deu") { return ["de-DE"] }
        if code.contains("spa") { return ["es-ES"] }
        if code.contains("tur") { return ["tr-TR"] }
        return ["en-US"]
    }
    #endif

    // MARK: - Tesseract (SwiftyTesseract)

    #if canImport(SwiftyTesseract)
    private func performTesseractOCR(
        imagePath: String,
        language: String,
        engineMode: EngineMode,
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

        // Configure Tesseract. The language argument is `+`-separated ISO
        // 639-3 codes; SwiftyTesseract models these as a fixed enum, so each
        // code is resolved through the generated table below.
        let languageCodes = language.split(separator: "+").map { String($0) }
        var recognitionLanguages: [RecognitionLanguage] = []
        for code in languageCodes {
            guard let resolved = Self.recognitionLanguage(for: code) else {
                result(FlutterError(
                    code: "INVALID_LANGUAGE",
                    message: "Unknown Tesseract language code \(code)",
                    details: nil
                ))
                return
            }
            recognitionLanguages.append(resolved)
        }
        if recognitionLanguages.isEmpty {
            recognitionLanguages = [.english]
        }

        let tesseract = Tesseract(
            languages: recognitionLanguages,
            engineMode: engineMode
        ) { tessBaseAPI in
            guard let options = config?["options"] as? [String: String] else { return }
            for (key, value) in options where Tesseract.Variable(rawValue: key) != nil {
                TessBaseAPISetVariable(tessBaseAPI, key, value)
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

            let timeoutWorkItem = DispatchWorkItem {
                completeOnce(FlutterError(
                    code: "OCR_TIMEOUT",
                    message: "OCR operation timed out after 30 seconds",
                    details: nil
                ))
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: timeoutWorkItem)

            let ocrResult = tesseract.performOCR(on: imageData)
            timeoutWorkItem.cancel()

            switch ocrResult {
            case .success(let recognizedText):
                completeOnce(recognizedText)
            case .failure(let error):
                completeOnce(FlutterError(
                    code: "OCR_PROCESS_ERROR",
                    message: "Tesseract OCR failed: \(error.localizedDescription)",
                    details: nil
                ))
            }
        }
    }
    #endif
}

// MARK: - RecognitionLanguage lookup

extension SwiftTesseractOcrPlugin {
    /// Maps a Tesseract language code (ISO 639-3, e.g. `eng`, `tur`) onto a
    /// [RecognitionLanguage].
    ///
    /// SwiftyTesseract 4.0.1 models languages as a fixed enum with no string
    /// initialiser and no `CaseIterable` conformance, so the code → case table
    /// is spelled out. It is generated from the enum's own `description`
    /// switch, so it stays complete as long as this table is regenerated with
    /// the dependency.
    static func recognitionLanguage(for code: String) -> RecognitionLanguage? {
        switch code.lowercased() {
        case "afr": return .afrikaans
        case "sqi": return .albanian
        case "amh": return .amharic
        case "ara": return .arabic
        case "asm": return .assamese
        case "aze": return .azerbaijani
        case "aze_cyrl": return .azerbaijaniCyrillic
        case "eus": return .basque
        case "bel": return .belarusian
        case "ben": return .bengali
        case "bos": return .bosnian
        case "bul": return .bulgarian
        case "mya": return .burmese
        case "cat": return .catalanAndValencian
        case "ceb": return .cebuano
        case "khm": return .centralKhmer
        case "chr": return .cherokee
        case "chi_sim": return .chineseSimplified
        case "chi_tra": return .chineseTraditional
        case "hrv": return .croatian
        case "ces": return .czech
        case "dan": return .danish
        case "nld": return .dutchFlemish
        case "dzo": return .dzongkha
        case "eng": return .english
        case "enm": return .englishMiddle
        case "epo": return .esperanto
        case "est": return .estonian
        case "fin": return .finnish
        case "frk": return .frankish
        case "fra": return .french
        case "frm": return .frenchMiddle
        case "glg": return .galician
        case "kat": return .georgian
        case "kat_old": return .georgianOld
        case "deu": return .german
        case "grc": return .greekAncient
        case "ell": return .greekModern
        case "guj": return .guajarati
        case "hat": return .haitian
        case "heb": return .hebrew
        case "hin": return .hindi
        case "hun": return .hungarian
        case "isl": return .icelandic
        case "ind": return .indonesian
        case "iku": return .inuktitut
        case "gle": return .irish
        case "ita": return .italian
        case "ita_old": return .italianOld
        case "jpn": return .japanese
        case "jav": return .javanese
        case "kan": return .kannada
        case "kaz": return .kazakh
        case "kor": return .korean
        case "kur": return .kurdish
        case "kir": return .kyrgyz
        case "lao": return .lao
        case "lat": return .latin
        case "lit": return .lithuanian
        case "mkd": return .macedonian
        case "msa": return .malay
        case "mal": return .malayalam
        case "mlt": return .maltese
        case "mar": return .marathi
        case "nep": return .nepali
        case "nor": return .norwegian
        case "ori": return .oriya
        case "pus": return .pashto
        case "fas": return .persian
        case "pol": return .polish
        case "por": return .portugese
        case "pan": return .punjabi
        case "ron": return .romanian
        case "rus": return .russian
        case "san": return .sanskrit
        case "srp": return .serbian
        case "srp_ltn": return .serbianLatin
        case "sin": return .sinhala
        case "slk": return .slovak
        case "slv": return .slovenian
        case "spa": return .spanish
        case "spa_old": return .spanishOld
        case "swa": return .swahili
        case "swe": return .swedish
        case "syr": return .syriac
        case "tgl": return .tagalog
        case "tgk": return .tajik
        case "tam": return .tamil
        case "tel": return .telugu
        case "tha": return .thai
        case "bod": return .tibetan
        case "tir": return .tigrinya
        case "tur": return .turkish
        case "uig": return .uighur
        case "ukr": return .ukrainian
        case "urd": return .urdu
        case "uzb": return .uzbek
        case "uzb_cyrl": return .uzbekCyrillic
        case "vie": return .vietnamese
        case "cym": return .welsh
        case "yid": return .yiddish
        default: return nil
        }
    }
}
