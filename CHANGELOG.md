## 0.4.1

*   Fixed potential asset loading path duplication on certain platforms (e.g., M1) by adjusting the internal asset path constant.

## 0.4.0

*   **Added Support for Multiple OCR Engines:** Introduced `OCRConfig` to allow selecting between Apple Vision (iOS) and Tesseract engines.
*   **Added Support for SwiftyTesseract 4.0.1 (iOS via CocoaPods):** Implemented a custom CocoaPods setup with local podspecs (`SwiftyTesseract401.podspec` and `libtesseract.podspec`) to enable using SwiftyTesseract 4.0.1, which is otherwise Swift Package Manager only. Users must manually include `libtesseract.xcframework` in their iOS project. See `CUSTOM_PODS_README.md` for details.
*   Updated example app to demonstrate engine selection.
*   Added support for the latest Dart SDK.

## 0.1.0

* Extract Text from images, Especially helpful when you are extracting single character images.

## 0.1.1

* fixed path references

## 0.1.2

* added description

## 0.1.2+1

* fixed typo

## 0.1.2+2

* fixed description

## 0.1.2+3

* added LICENSE
## 0.1.3

* updated swift version to 4.2

## 0.2.0

* fixed dependecies

## 0.2.1

* fixed swift version

## 0.2.2

* set target swift version to 4.2

## 0.3.0

* added language support you can pass the language as an optional parameter. TesseractOcr.extractText(imagePath, language: "financial");
if not set it will default to "eng". language must match the name of .traineddata file