#import "TesseractOcrPlugin.h"
#import <tesseract_ocr/tesseract_ocr-Swift.h>

@implementation TesseractOcrPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftTesseractOcrPlugin registerWithRegistrar:registrar];
}
@end
