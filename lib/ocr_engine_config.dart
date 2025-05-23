/// OCR Engine configuration for tesseract_ocr plugin.
///
/// This file contains configuration options for the OCR engines
/// supported by the tesseract_ocr plugin.
library tesseract_ocr.config;

/// OCR Engine type
enum OCREngine {
  /// Apple Vision OCR engine (iOS only)
  vision,

  /// Tesseract OCR engine (iOS and Android)
  tesseract,

  /// Default engine - platform specific
  /// On iOS: Vision
  /// On Android: Tesseract
  defaultEngine,
}

/// Common Tesseract configuration variable names
class TesseractConfig {
  /// Whether to preserve spacing between words (1 or 0)
  static const String preserveInterwordSpaces = 'preserve_interword_spaces';
  
  /// The page segmentation mode (PSM)
  static const String pageSegMode = 'tessedit_pageseg_mode';
  
  /// The OCR engine mode (OEM)
  static const String ocrEngineMode = 'tessedit_ocr_engine_mode';
  
  /// Path to a debug output file
  static const String debugFile = 'debug_file';
}

/// Page Segmentation Modes for Tesseract
class PageSegmentationMode {
  /// Orientation and script detection only
  static const String osd = '0';
  
  /// Automatic page segmentation with OSD
  static const String autoOsd = '1';
  
  /// Automatic page segmentation, no OSD, no OCR
  static const String autoOnly = '2';
  
  /// Fully automatic page segmentation, no OSD (default)
  static const String auto = '3';
  
  /// Assume a single column of text of variable sizes
  static const String singleColumn = '4';
  
  /// Assume a single uniform block of vertically aligned text
  static const String singleBlockVertText = '5';
  
  /// Assume a single uniform block of text
  static const String singleBlock = '6';
  
  /// Treat the image as a single text line
  static const String singleLine = '7';
  
  /// Treat the image as a single word
  static const String singleWord = '8';
  
  /// Treat the image as a single character
  static const String singleChar = '9';
  
  /// Sparse text - Find as much text as possible in no particular order
  static const String sparseText = '10';
  
  /// Sparse text with OSD
  static const String sparseTextOsd = '11';
  
  /// Raw line - Treat the image as a single text line, bypassing hacks that are Tesseract-specific
  static const String rawLine = '12';
}

/// Configuration for OCR operations
class OCRConfig {
  /// The language to use for OCR
  final String language;

  /// The OCR engine to use
  final OCREngine engine;

  /// Path to tessdata folder (only used with Tesseract engine)
  final String? tessDataPath;

  /// Additional options for OCR engine
  /// 
  /// These values are passed directly to the OCR engine.
  /// For Tesseract, any valid Tesseract configuration variable can be set.
  /// 
  /// Common Tesseract options include:
  /// - 'preserve_interword_spaces': '0' or '1' (preserve spaces between words)
  /// - 'tessedit_pageseg_mode': Page segmentation mode (see [PageSegmentationMode])
  /// - 'tessedit_ocr_engine_mode': OCR engine mode (0-3)
  /// - Any other valid Tesseract configuration variables
  final Map<String, dynamic>? options;

  /// Creates a new OCR configuration
  const OCRConfig({
    this.language = 'eng',
    this.engine = OCREngine.defaultEngine,
    this.tessDataPath,
    this.options,
  });

  /// Convert this configuration to a map that can be passed to the platform channel
  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'language': language,
      'engine': engine.toString().split('.').last,
    };

    if (tessDataPath != null) {
      map['tessDataPath'] = tessDataPath;
    }

    if (options != null) {
      map.addAll(options!);
    }

    return map;
  }
}