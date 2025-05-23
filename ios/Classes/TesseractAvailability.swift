import Foundation

/// Helper class to check for SwiftyTesseract availability
public class TesseractAvailability {
    
    /// Returns whether SwiftyTesseract is available in the current build
    @objc public static func isSwiftyTesseractAvailable() -> Bool {
        #if canImport(SwiftyTesseractLocal)
        return true
        #else
        return false
        #endif
    }
    
    /// Returns a string description of the current availability state
    @objc public static func availabilityDescription() -> String {
        #if canImport(SwiftyTesseractLocal)
        return "SwiftyTesseractLocal is available in this build"
        #else
        return "SwiftyTesseractLocal is NOT available. Add -DUSE_SWIFTY_TESSERACT to Other Swift Flags in Runner target, or check pod integration."
        #endif
    }
    
    /// Returns a dictionary with detailed availability information
    @objc public static func availabilityInfo() -> [String: Any] {
        #if canImport(SwiftyTesseractLocal)
        return [
            "available": true,
            "reason": "SwiftyTesseractLocal module found",
            "buildFlag": "USE_SWIFTY_TESSERACT (implies SwiftyTesseractLocal)",
        ]
        #else
        return [
            "available": false,
            "reason": "SwiftyTesseractLocal module not found. Ensure 'SwiftyTesseractLocal' pod is correctly integrated and USE_SWIFTY_TESSERACT flag is set.",
            "buildFlag": "USE_SWIFTY_TESSERACT not defined or module link error",
        ]
        #endif
    }
    
    /// Attempts to dynamically check if SwiftyTesseract can actually be used at runtime
    @objc public static func canCreateTesseractInstance() -> Bool {
        #if canImport(SwiftyTesseractLocal)
        do {
            // Try to use a SwiftyTesseract class or method to verify it's actually available
            // The actual class name might be SwiftyTesseractLocal.SwiftyTesseract if the module name is SwiftyTesseractLocal
            // and the class name within that module is SwiftyTesseract.
            // Or it could be just SwiftyTesseract if the module map handles this.
            // For now, let's assume the module name is the prefix.
            let className = NSClassFromString("SwiftyTesseractLocal.SwiftyTesseract")
            return className != nil
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}