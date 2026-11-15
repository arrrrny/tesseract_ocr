#import <FlutterMacOS/FlutterMacOS.h>

NS_ASSUME_NONNULL_BEGIN

/// The name the generated plugin registrant imports. The implementation is the
/// shared Swift plugin (Sources/tesseract_ocr/SwiftTesseractOcrPlugin.swift);
/// this class only forwards the registration call to it, so macOS and iOS
/// expose the same plugin name to the registrant.
@interface TesseractOcrPlugin : NSObject<FlutterPlugin>
@end

NS_ASSUME_NONNULL_END