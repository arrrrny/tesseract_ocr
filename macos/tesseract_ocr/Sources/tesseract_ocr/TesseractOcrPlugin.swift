import Cocoa
import FlutterMacOS

public class TesseractOcrPlugin: NSObject, FlutterPlugin {
  private let ocrQueue = DispatchQueue(label: "com.tesseract.ocr", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "tesseract_ocr",
      binaryMessenger: registrar.messenger
    )
    let instance = TesseractOcrPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "extractText", "extractHocr":
      handleExtract(call: call, isHocr: call.method == "extractHocr", result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleExtract(
    call: FlutterMethodCall,
    isHocr: Bool,
    result: @escaping FlutterResult
  ) {
    guard let params = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Arguments were invalid or could not be parsed.",
          details: nil
        )
      )
      return
    }

    let config = params["config"] as? [String: Any]
    let engine = (params["engine"] as? String) ?? (config?["engine"] as? String)
    if let engine = engine, engine.lowercased() == "vision" {
      result(
        FlutterError(
          code: "UNSUPPORTED_ENGINE",
          message:
            "Apple Vision engine is only supported on iOS. Use OCREngine.tesseract or OCREngine.defaultEngine on macOS.",
          details: nil
        )
      )
      return
    }

    let fileManager = FileManager.default

    // The Dart layer sends the encoded image when the caller has bytes. This
    // plugin drives the `tesseract` executable, which reads a path, so the bytes
    // are written to a temporary file that is removed again when the run ends.
    let imageBytes = (params["imageBytes"] as? FlutterStandardTypedData)?.data
    let imagePath: String
    let imageLabel: String
    let temporaryImagePath: String?
    if let imageBytes = imageBytes, !imageBytes.isEmpty {
      let temporaryPath = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("tesseract_ocr-\(UUID().uuidString).img")
      do {
        try imageBytes.write(to: URL(fileURLWithPath: temporaryPath))
      } catch {
        result(
          FlutterError(
            code: "IMAGE_LOAD_FAILED",
            message:
              "Could not write the image bytes to a temporary file: \(error.localizedDescription)",
            details: nil
          )
        )
        return
      }
      imagePath = temporaryPath
      imageLabel = "in-memory image"
      temporaryImagePath = temporaryPath
    } else {
      temporaryImagePath = nil
      guard let path = params["imagePath"] as? String, !path.isEmpty else {
        result(
          FlutterError(
            code: "MISSING_PARAMS",
            message: "Required parameter 'imagePath' is missing.",
            details: nil
          )
        )
        return
      }

      guard !path.contains(where: { ";|&$`\n\r".contains($0) }) else {
        result(
          FlutterError(
            code: "INVALID_PATH",
            message: "Image path contains invalid characters",
            details: nil
          )
        )
        return
      }

      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
        result(
          FlutterError(
            code: "IMAGE_NOT_FOUND",
            message: "Image file does not exist at path: \(path)",
            details: nil
          )
        )
        return
      }

      if isDirectory.boolValue {
        result(
          FlutterError(
            code: "IMAGE_LOAD_FAILED",
            message: "Expected an image file but found a directory at path: \(path)",
            details: nil
          )
        )
        return
      }

      guard fileManager.isReadableFile(atPath: path) else {
        result(
          FlutterError(
            code: "IMAGE_UNREADABLE",
            message: "Image file is not readable at path: \(path)",
            details: nil
          )
        )
        return
      }

      if let attributes = try? fileManager.attributesOfItem(atPath: path),
         let fileSize = attributes[.size] as? NSNumber,
         fileSize.int64Value == 0 {
        result(
          FlutterError(
            code: "IMAGE_LOAD_FAILED",
            message: "Image file is empty at path: \(path)",
            details: nil
          )
        )
        return
      }

      imagePath = path
      imageLabel = path
    }

    let rawLanguage =
      (params["language"] as? String) ?? (config?["language"] as? String) ?? "eng"
    let trimmedLanguage = rawLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
    let language = trimmedLanguage.isEmpty ? "eng" : trimmedLanguage

    let rawTessData =
      (params["tessData"] as? String) ?? (config?["tessDataPath"] as? String)
    guard let tessDataBase = rawTessData?.trimmingCharacters(in: .whitespacesAndNewlines),
          !tessDataBase.isEmpty else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Data path must not be null! Ensure tessdata is properly loaded.",
          details: nil
        )
      )
      return
    }

    guard let resolvedTessDataDir = resolveTessDataDirectory(
      basePath: tessDataBase,
      language: language,
      fileManager: fileManager
    ) else {
      let languageParts = language.split(separator: "+").map { String($0) }
      let missingFiles = languageParts
        .filter { !fileManager.fileExists(atPath: "\(tessDataBase)/\($0).traineddata") && !fileManager.fileExists(atPath: "\(tessDataBase)/tessdata/\($0).traineddata") }
        .map { "\($0).traineddata" }
      let detail = missingFiles.isEmpty
        ? "No tessdata directory found at '\(tessDataBase)'."
        : "Missing trained data file(s) \(missingFiles.joined(separator: ", ")) in '\(tessDataBase)'."
      result(
        FlutterError(
          code: "TESSDATA_NOT_FOUND",
          message:
            "\(detail) Ensure the .traineddata file is listed in assets/tessdata_config.json and bundled in assets/tessdata/.",
          details: nil
        )
      )
      return
    }

    guard let tesseractExecutable = findTesseractExecutable(fileManager: fileManager) else {
      result(
        FlutterError(
          code: "TESSERACT_NOT_FOUND",
          message:
            "Tesseract executable not found on this Mac. Install it with 'brew install tesseract' (or set TESSERACT_PATH).",
          details: nil
        )
      )
      return
    }

    var arguments: [String] = [
      imagePath,
      "stdout",
      "--tessdata-dir",
      resolvedTessDataDir,
      "-l",
      language,
    ]

    let mergedOptions = collectOptions(params: params, config: config)
    for key in mergedOptions.keys.sorted() {
      guard let rawValue = mergedOptions[key], !(rawValue is NSNull) else { continue }
      let value = "\(rawValue)"
      if key == Self.pageSegModeKey {
        arguments.append(contentsOf: ["--psm", value])
      } else if key == Self.ocrEngineModeKey {
        arguments.append(contentsOf: ["--oem", value])
      } else {
        arguments.append(contentsOf: ["-c", "\(key)=\(value)"])
      }
    }

    if isHocr {
      arguments.append("hocr")
    }

    ocrQueue.async {
      // A temporary file exists only for the bytes entry point, and the engine
      // has finished reading it by the time this closure ends — on the launch
      // failure path as much as on the normal one.
      defer {
        if let temporaryImagePath = temporaryImagePath {
          try? fileManager.removeItem(atPath: temporaryImagePath)
        }
      }

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

      let process = Process()
      process.executableURL = URL(fileURLWithPath: tesseractExecutable)
      process.arguments = arguments

      var environment = ProcessInfo.processInfo.environment
      let existingPath = environment["PATH"] ?? "/usr/bin:/bin"
      environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
      process.environment = environment

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      do {
        try process.run()
      } catch {
        completeOnce(
          FlutterError(
            code: "TESSERACT_LAUNCH_FAILED",
            message:
              "Failed to launch Tesseract at '\(tesseractExecutable)': \(error.localizedDescription). If App Sandbox is enabled, disable com.apple.security.app-sandbox in your macOS entitlements.",
            details: nil
          )
        )
        return
      }

      var stdoutData = Data()
      var stderrData = Data()
      let ioGroup = DispatchGroup()

      ioGroup.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        ioGroup.leave()
      }

      ioGroup.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        ioGroup.leave()
      }

      let timeoutWorkItem = DispatchWorkItem {
        if process.isRunning {
          process.terminate()
          completeOnce(
            FlutterError(
              code: "OCR_TIMEOUT",
              message: "OCR operation timed out after 30 seconds",
              details: nil
            )
          )
        }
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: timeoutWorkItem)

      ioGroup.wait()
      process.waitUntilExit()
      timeoutWorkItem.cancel()

      let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
      let stderrText = (String(data: stderrData, encoding: .utf8) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

      if process.terminationStatus == 0 {
        let cleaned = stdoutText.trimmingCharacters(
          in: CharacterSet(charactersIn: "\u{000C}")
        )
        completeOnce(cleaned)
      } else {
        let message = stderrText.isEmpty
          ? "Tesseract failed with exit status \(process.terminationStatus) for image '\(imageLabel)'."
          : "Tesseract failed (exit status \(process.terminationStatus)): \(stderrText)"
        completeOnce(
          FlutterError(
            code: "OCR_PROCESS_ERROR",
            message: message,
            details: nil
          )
        )
      }
    }
  }

  private func resolveTessDataDirectory(
    basePath: String,
    language: String,
    fileManager: FileManager
  ) -> String? {
    let languageParts = language
      .split(separator: "+")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let candidates = [
      basePath,
      (basePath as NSString).appendingPathComponent("tessdata"),
    ]

    for candidate in candidates {
      var isDir: ObjCBool = false
      guard fileManager.fileExists(atPath: candidate, isDirectory: &isDir),
            isDir.boolValue else {
        continue
      }
      if languageParts.isEmpty {
        return candidate
      }
      let allPresent = languageParts.allSatisfy { part in
        let trainedDataPath = (candidate as NSString).appendingPathComponent(
          "\(part).traineddata"
        )
        return fileManager.fileExists(atPath: trainedDataPath)
      }
      if allPresent {
        return candidate
      }
    }

    return nil
  }

  private func findTesseractExecutable(fileManager: FileManager) -> String? {
    var candidates: [String] = []
    if let overridePath = ProcessInfo.processInfo.environment["TESSERACT_PATH"],
       !overridePath.isEmpty {
      candidates.append(overridePath)
    }

    candidates.append(contentsOf: [
      "/opt/homebrew/bin/tesseract",
      "/usr/local/bin/tesseract",
      "/opt/local/bin/tesseract",
      "/usr/bin/tesseract",
    ])

    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
      for dir in pathEnv.split(separator: ":") {
        let candidate = (String(dir) as NSString).appendingPathComponent("tesseract")
        candidates.append(candidate)
      }
    }

    for candidate in candidates {
      if fileManager.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }

  // MARK: - Shared option names

  /// The OCR engine mode (OEM). Applied through its own call on Android and as
  /// `--oem` here, never as a `-c` variable.
  static let ocrEngineModeKey = "tessedit_ocr_engine_mode"

  /// The page segmentation mode (PSM).
  static let pageSegModeKey = "tessedit_pageseg_mode"

  /// Keys this plugin applies itself and must never forward as a variable.
  static let reservedOptionKeys: Set<String> = [
    "language",
    "engine",
    "tessDataPath",
    pageSegModeKey,
    ocrEngineModeKey,
  ]

  private func collectOptions(
    params: [String: Any],
    config: [String: Any]?
  ) -> [String: Any] {
    var collected: [String: Any] = [:]

    if let config = config {
      for (key, value) in config where !Self.reservedOptionKeys.contains(key) {
        collected[key] = value
      }
    }

    if let options = params["options"] as? [String: Any] {
      for (key, value) in options where !Self.reservedOptionKeys.contains(key) {
        collected[key] = value
      }
    }

    return collected
  }
}
