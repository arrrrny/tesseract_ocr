// The Flutter engine module is `Flutter` on iOS and `FlutterMacOS` on macOS;
// importing the wrong one is a hard compile error on the other platform, so the
// plugin picks by what the SDK actually ships.
#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif
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

        for key in rawOptions.keys.sorted() {
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

/// Where one recognition call takes its image from.
///
/// The Dart layer sends whichever form the caller has: a path for
/// `extractText`, the encoded bytes for `extractTextFromBytes`. The engines
/// differ in what they can consume — the Tesseract core reads a memory buffer,
/// Vision wraps a `UIImage` — so the call resolves the source once and each
/// engine takes what it needs from it.
enum OcrImageSource {
    case path(String)
    case data(Data)

    /// The image data, read from the path when that is the source.
    ///
    /// A path that cannot be read is a load failure, not an empty image: the
    /// caller pointed at a file that is gone or unreadable.
    func loadData() -> Data? {
        switch self {
        case .path(let path):
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        case .data(let data):
            return data
        }
    }

    /// How a log line or an error names this source.
    var description: String {
        switch self {
        case .path(let path):
            return "path: \(path)"
        case .data(let data):
            return "\(data.count) bytes"
        }
    }
}

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
            handleExtract(call: call, isHocr: false, result: result)
        case "extractHocr":
            handleExtract(call: call, isHocr: true, result: result)
        case "isSupported":
            handleIsSupported(result: result)
        case "detectOrientationScript":
            handleDetectOrientationScript(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleDetectOrientationScript(call: FlutterMethodCall, result: @escaping FlutterResult) {
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

        let rawConfig = (args["config"] as? [String: Any]) ?? args
        // OSD is a Tesseract engine capability; Vision has no orientation &
        // script detection, so refuse it rather than guessing.
        if (rawConfig["engine"] as? String)?.lowercased() == "vision" {
            result(FlutterError(
                code: "UNSUPPORTED_ENGINE",
                message: "Apple Vision engine does not support OSD. Use OCREngine.tesseract or OCREngine.defaultEngine.",
                details: nil
            ))
            return
        }

        #if canImport(SwiftyTesseract)
        let language = (args["language"] as? String) ?? "osd"
        let tessData = args["tessData"] as? String
        // The same passthrough the OCR path applies: any Tesseract variable
        // the caller set reaches the engine instead of being silently dropped.
        let options = (args["options"] as? [String: Any])
            ?? (rawConfig["options"] as? [String: Any])
        performTesseractOsd(
            imagePath: imagePath,
            language: language,
            options: options,
            tessData: tessData,
            result: result
        )
        #else
        result(FlutterError(
            code: "NOT_SUPPORTED",
            message: "Orientation & script detection requires Tesseract on this platform.",
            details: nil
        ))
        #endif
    }

    private func handleIsSupported(result: @escaping FlutterResult) {
        #if canImport(SwiftyTesseract)
        result(true)
        #else
        result(false)
        #endif
    }

    private func handleExtract(
        call: FlutterMethodCall,
        isHocr: Bool,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Arguments were invalid or missing",
                details: nil
            ))
            return
        }

        // The Dart layer sends the image as bytes when the caller has bytes.
        // A path is still required when it does not: a recognition without any
        // image is a caller mistake, not an empty result.
        let imageBytes = (args["imageBytes"] as? FlutterStandardTypedData)?.data
        let imagePath = args["imagePath"] as? String
        let imageSource: OcrImageSource
        if let imageBytes = imageBytes, !imageBytes.isEmpty {
            imageSource = .data(imageBytes)
        } else if let imagePath = imagePath, !imagePath.isEmpty {
            imageSource = .path(imagePath)
        } else {
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

        // Resolve the engine locally. The Dart side sends a plain string
        // ("vision" / "tesseract" / "defaultEngine"). Only "vision" routes to
        // Apple Vision; every other value (including the "defaultEngine" sent by
        // the historical default) stays on Tesseract so an iOS caller that omits
        // `engine` keeps using tessData/options/languages instead of silently
        // being downgraded to Vision (en/fr/de/es only).
        let engineString = (rawConfig["engine"] as? String)?.lowercased()
        let useVision = (engineString == "vision")

        // hOCR is a Tesseract output format; Apple Vision produces none. Reject
        // the combination rather than silently returning empty output.
        if isHocr && useVision {
            result(FlutterError(
                code: "UNSUPPORTED_ENGINE",
                message: "hOCR output requires the Tesseract engine; OCREngine.vision does not produce hOCR.",
                details: nil
            ))
            return
        }

        #if canImport(UIKit) && canImport(SwiftyTesseract) && !os(macOS)
        if useVision {
            performVisionOCR(
                imageSource: imageSource,
                language: language,
                config: rawConfig,
                result: result
            )
        } else {
            performTesseractOCR(
                imageSource: imageSource,
                language: language,
                tessData: tessData,
                config: rawConfig,
                isHocr: isHocr,
                result: result
            )
        }
        #elseif canImport(SwiftyTesseract)
        if useVision {
            result(FlutterError(
                code: "UNSUPPORTED_ENGINE",
                message: "Apple Vision engine is only supported on iOS. Use OCREngine.tesseract or OCREngine.defaultEngine on this platform.",
                details: nil
            ))
            return
        }
        performTesseractOCR(
            imageSource: imageSource,
            language: language,
            tessData: tessData,
            config: rawConfig,
            isHocr: isHocr,
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
        imageSource: OcrImageSource,
        language: String,
        config: [String: Any]?,
        result: @escaping FlutterResult
    ) {
        let options = VisionOcrOptions.resolve(
            (config)?["options"] as? [String: Any]
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
        
        // Vision reads a UIImage, which it can build from a path or from the
        // encoded bytes directly — no temporary file either way.
        let image: UIImage?
        switch imageSource {
        case .path(let path):
            image = UIImage(contentsOfFile: path)
        case .data(let data):
            image = UIImage(data: data)
        }

        guard let image = image, let cgImage = image.cgImage else {
            result(FlutterError(
                code: "IMAGE_LOAD_FAILED",
                message: "Could not load image from \(imageSource.description)",
                details: nil
            ))
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest { (request, error) in
            // The completion runs on Vision's own queue; reply on the main queue
            // like every other path. `self` is not needed here, so there is no
            // weak capture that could drop the reply if the plugin deallocates.
            if let error = error {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_ERROR",
                        message: "Vision OCR failed: \(error.localizedDescription)",
                        details: nil
                    ))
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_NO_RESULTS",
                        message: "No text observations found",
                        details: nil
                    ))
                }
                return
            }

            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            let text = recognizedStrings.joined(separator: "\n")
            DispatchQueue.main.async {
                result(text)
            }
        }

        request.recognitionLevel = options.recognitionLevel
        request.usesLanguageCorrection = options.usesLanguageCorrection
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

        // Flutter bundles assets under `flutter_assets` inside the app/framework
        // bundle, so the Dart-provided `tessData` path is the only candidate that
        // reliably resolves on iOS and macOS. `Bundle.main.resourceURL/tessdata`
        // and `.../flutter_assets/assets/tessdata` never exist in a real Flutter
        // app, so they are not worth probing.
        var candidates: [String] = []
        if let tessData = tessData?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tessData.isEmpty {
            candidates.append(tessData)
            candidates.append((tessData as NSString).appendingPathComponent("tessdata"))
        }

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
        imageSource: OcrImageSource,
        language: String,
        tessData: String?,
        config: [String: Any]?,
        isHocr: Bool,
        result: @escaping FlutterResult
    ) {
        // A path reaches Tesseract from the shell-facing entry points, so it is
        // validated for shell metacharacters; bytes never do.
        if case .path(let path) = imageSource {
            let invalidChars = CharacterSet(charactersIn: ";|&$`\n\r")
            if path.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
                result(FlutterError(
                    code: "INVALID_PATH",
                    message: "Image path contains invalid characters",
                    details: nil
                ))
                return
            }
        }

        // The Tesseract core reads a memory buffer, so both sources end up as
        // bytes: a path is read here, the bytes are already here.
        guard let imageData = imageSource.loadData() else {
            result(FlutterError(
                code: "IMAGE_LOAD_FAILED",
                message: "Could not load image from \(imageSource.description)",
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
            let basePathDescription = (tessData?.isEmpty == false) ? tessData! : "tessdata (provided by the app)"
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

        // Determine engine mode. SwiftyTesseract 4.0.1 defines `EngineMode` as a
        // typealias of `TessOcrEngineMode` with members: tesseractOnly, lstmOnly,
        // tesseractLstmCombined, default (no `defaultEngine`).
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
                engineMode = .default
            }
        } else {
            engineMode = .lstmOnly
        }

        // Perform OCR on a serial queue to prevent race conditions.
        //
        // The Tesseract handle is created, initialized, used, ended and deleted
        // ALL inside this dispatched closure: a `defer` at function scope would
        // run as soon as the outer function returned, deleting the handle before
        // the async block touches it (use-after-free).
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

            // Create Tesseract instance against the validated tessdata path via TessBaseAPI
            guard let tessBaseAPI = TessBaseAPICreate() else {
                completeOnce(FlutterError(
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
                completeOnce(FlutterError(
                    code: "OCR_INIT_FAILED",
                    message: "Failed to initialize Tesseract with language '\(language)' at '\(validatedTessData.directoryPath)' (code: \(initReturnCode)). Ensure \(validatedTessData.trainedDataFiles.joined(separator: ", ")) matches the selected engine mode.",
                    details: nil
                ))
                return
            }

            if let options = config?["options"] as? [String: Any] {
                applyTesseractVariables(options, to: tessBaseAPI)
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
            //
            // `withUnsafeBytes` hands over an `UnsafeRawBufferPointer` whose
            // base address is an `UnsafeRawPointer?`; `pixReadMem` wants an
            // `UnsafePointer<UInt8>`, so bind the memory explicitly to UInt8.
            // pixReadMem copies the bytes, so the buffer is only needed for the
            // duration of this call.
            let pix = imageData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> OpaquePointer? in
                guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return nil
                }
                return pixReadMem(base, imageData.count)
            }
            guard let pix = pix else {
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

            // hOCR is the layout-aware format (bounding boxes per word/line);
            // plain UTF-8 text is the default. Both come from libtesseract's C
            // API and are freed the same way.
            let textPtr: UnsafeMutablePointer<Int8>? = isHocr
                ? TessBaseAPIGetHOCRText(tessBaseAPI, 0)
                : TessBaseAPIGetUTF8Text(tessBaseAPI)
            guard recognized, let textPtr = textPtr else {
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

    /// Applies the caller's Tesseract variables to the engine handle, coercing
    /// each value the way `TessBaseAPISetVariable` needs (strings verbatim,
    /// booleans as 1/0, numbers through NSNumber's string form). Shared by the
    /// OCR and OSD paths so both honour `OCRConfig.options` the same way.
    private func applyTesseractVariables(
        _ options: [String: Any],
        to tessBaseAPI: OpaquePointer?
    ) {
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

    private func performTesseractOsd(
        imagePath: String,
        language: String,
        options: [String: Any]?,
        tessData: String?,
        result: @escaping FlutterResult
    ) {
        // Validate image path contains no shell metacharacters.
        let invalidChars = CharacterSet(charactersIn: ";|&$`\n\r")
        if imagePath.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
            result(FlutterError(
                code: "INVALID_PATH",
                message: "Image path contains invalid characters",
                details: nil
            ))
            return
        }

        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) else {
            result(FlutterError(
                code: "IMAGE_LOAD_FAILED",
                message: "Could not load image at path: \(imagePath)",
                details: nil
            ))
            return
        }

        guard let validatedTessData = validateTessData(language: language, tessData: tessData) else {
            result(FlutterError(
                code: "TESSDATA_NOT_FOUND",
                message: "Missing or unreadable traineddata for language '\(language)' in the tessdata directory at '\(tessData ?? "tessdata (provided by the app)")'. Orientation & script detection needs a legacy-capable model such as osd.traineddata.",
                details: nil
            ))
            return
        }

        // The handle is created, used and destroyed ALL inside the dispatched
        // closure: a `defer` at function scope would end it before the async
        // block runs (use-after-free), the same rule performTesseractOCR follows.
        DispatchQueue(label: "com.tesseract.osd", qos: .userInitiated).async {
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

            guard let tessBaseAPI = TessBaseAPICreate() else {
                completeOnce(FlutterError(
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
                .default
            )
            guard initReturnCode == 0 else {
                completeOnce(FlutterError(
                    code: "OCR_INIT_FAILED",
                    message: "Failed to initialize Tesseract for OSD with language '\(language)' at '\(validatedTessData.directoryPath)' (code: \(initReturnCode)).",
                    details: nil
                ))
                return
            }

            if let options = options {
                applyTesseractVariables(options, to: tessBaseAPI)
            }

            // `TessBaseAPIDetectOrientationScript` blocks on this queue with no
            // watchdog of its own, so the same 30s timeout the OCR path arms
            // guards here too: a hung decode answers OSD_TIMEOUT instead of
            // parking the caller's future forever.
            let timeoutWorkItem = DispatchWorkItem {
                completeOnce(FlutterError(
                    code: "OSD_TIMEOUT",
                    message: "Orientation & script detection timed out after 30 seconds",
                    details: nil
                ))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: timeoutWorkItem)

            // `withUnsafeBytes` yields an UnsafeRawBufferPointer; pixReadMem wants
            // an UnsafePointer<UInt8>, so bind the memory explicitly to UInt8.
            let pix = imageData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> OpaquePointer? in
                guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return nil
                }
                return pixReadMem(base, imageData.count)
            }
            guard let pix = pix else {
                timeoutWorkItem.cancel()
                completeOnce(FlutterError(
                    code: "OCR_PROCESS_ERROR",
                    message: "Failed to decode image data for OSD.",
                    details: nil
                ))
                return
            }
            defer {
                pixDestroy(pix)
            }

            TessBaseAPISetImage2(tessBaseAPI, pix)

            var orientDeg: Int32 = 0
            var orientConf: Float = 0
            var scriptConf: Float = 0
            var scriptName: UnsafePointer<Int8>?
            let detected = TessBaseAPIDetectOrientationScript(
                tessBaseAPI,
                &orientDeg,
                &orientConf,
                &scriptName,
                &scriptConf
            ) != 0
            timeoutWorkItem.cancel()

            let script = scriptName.map { String(cString: $0) } ?? ""
            if let scriptName = scriptName {
                TessDeleteText(scriptName)
            }

            if detected {
                completeOnce([
                    "orientation": Int(orientDeg),
                    "orientation_conf": Double(orientConf),
                    "script": script,
                    "script_conf": Double(scriptConf),
                ])
            } else {
                completeOnce(FlutterError(
                    code: "OSD_FAILED",
                    message: "Tesseract could not detect orientation & script. Ensure a legacy-capable traineddata (e.g. osd.traineddata) is bundled.",
                    details: nil
                ))
            }
        }
    }
    #endif
}
