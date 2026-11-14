import Foundation

/// Helper class to check for SwiftyTesseract availability
public class TesseractAvailability {
    
    /// Returns whether SwiftyTesseract is available in the current build
    @objc public static func isSwiftyTesseractAvailable() -> Bool {
        #if canImport(SwiftyTesseract)
        return true
        #else
        return false
        #endif
    }
    
    /// Returns a string description of the current availability state
    @objc public static func availabilityDescription() -> String {
        #if canImport(SwiftyTesseract)
        return "SwiftyTesseract is available in this build"
        #else
        return "SwiftyTesseract is NOT available. Add -DUSE_SWIFTY_TESSERACT to Other Swift Flags in Runner target, or check pod integration."
        #endif
    }
    
    /// Returns a dictionary with detailed availability information
    @objc public static func availabilityInfo() -> [String: Any] {
        #if canImport(SwiftyTesseract)
        return [
            "available": true,
            "reason": "SwiftyTesseract module found",
            "buildFlag": "USE_SWIFTY_TESSERACT (implies SwiftyTesseract)",
        ]
        #else
        return [
            "available": false,
            "reason": "SwiftyTesseract module not found. Ensure the SwiftyTesseract401 pod is correctly integrated and USE_SWIFTY_TESSERACT flag is set.",
            "buildFlag": "USE_SWIFTY_TESSERACT not defined or module link error",
        ]
        #endif
    }
    
    /// Attempts to dynamically check if SwiftyTesseract can actually be used at runtime
    @objc public static func canCreateTesseractInstance() -> Bool {
        #if canImport(SwiftyTesseract)
        do {
            // Verify a SwiftyTesseract class is actually linked in — the module
            // (provided by the SwiftyTesseract401 podspec) is imported, and the
            // class lives at module-qualified name SwiftyTesseract.<Class>.
            let className = NSClassFromString("SwiftyTesseract.SwiftyTesseract")
            return className != nil
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}