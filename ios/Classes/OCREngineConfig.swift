import Foundation

/// OCR Engine options
public enum OCREngine: String {
    case appleVision = "vision"
    case swiftyTesseract = "tesseract"
    
    static func fromString(_ string: String?) -> OCREngine {
        guard let engineString = string, 
              let engine = OCREngine(rawValue: engineString) else {
            // Default to appleVision if not specified or invalid
            return .appleVision
        }
        return engine
    }
}

/// Singleton class to manage OCR engine configuration
public class OCREngineConfig {
    /// Shared instance for global access
    public static let shared = OCREngineConfig()
    
    private init() {}
    
    /// The OCR engine to use - defaults to Apple Vision
    public var engine: OCREngine = .appleVision
    
    /// Configure the OCR engine from parameters
    public func configure(fromParams params: [String: Any]?) {
        if let engineString = params?["engine"] as? String {
            engine = OCREngine.fromString(engineString)
        }
    }
    
    /// Check if the selected engine is available
    public func isSelectedEngineAvailable() -> Bool {
        switch engine {
        case .appleVision:
            return true // Vision is always available on iOS 14+
        case .swiftyTesseract:
            #if canImport(SwiftyTesseract)
            return TesseractAvailability.isSwiftyTesseractAvailable()
            #else
            return false
            #endif
        }
    }
    
    /// Get a description of the current engine configuration
    public func description() -> String {
        switch engine {
        case .appleVision:
            return "Using Apple Vision OCR engine"
        case .swiftyTesseract:
            #if canImport(SwiftyTesseract)
            return "Using SwiftyTesseract OCR engine"
            #else
            return "SwiftyTesseract selected but not available"
            #endif
        }
    }
}