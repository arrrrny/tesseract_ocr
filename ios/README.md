# iOS Tesseract OCR Integration

This Flutter plugin uses two different OCR engines depending on the platform:

1. **iOS 13+ Devices**: Uses Apple's Vision framework for OCR
2. **Android Devices**: Uses Tesseract OCR engine

## iOS Implementation Notes

The iOS implementation leverages Vision framework's text recognition capabilities, which provides:
- Built-in, efficient OCR with no external dependencies
- Language detection and multi-language support
- High accuracy text recognition

### Requirements

- iOS 13.0 or later
- Swift 5.0+

### Language Support

For iOS 13-15, the Vision implementation supports the following languages:
- English (en-US)
- French (fr-FR)
- German (de-DE)
- Spanish (es-ES)

For iOS 16+, automatic language detection is used.

### Tesseract Language Parameter

While the plugin accepts a language parameter for consistency with Android, on iOS:
- The language parameter is used to determine which Vision language to use
- If the language is not explicitly supported, the system will default to English
- On iOS 16+, the system will automatically detect the language

## Testing

The OCR results may vary between platforms due to using different OCR engines. For consistent behavior across platforms, you may want to:

1. Test on both iOS and Android devices
2. Try different image formats and resolutions
3. Pre-process images for better OCR results (like increasing contrast or sharpness)

## Troubleshooting

If OCR results are poor or inconsistent:
1. Ensure the image is clear and has good contrast
2. Try using a different language setting if the text is not in English
3. Consider pre-processing the image to improve text clarity