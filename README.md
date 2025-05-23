# Tesseract OCR for Flutter

A Flutter plugin that provides Optical Character Recognition (OCR) capabilities using Tesseract (v4.x) and Apple Vision (iOS).

This plugin utilizes:
*   **Android:** [Tesseract4Android](https://github.com/adaptech-cz/Tesseract4Android/)
*   **iOS:** [SwiftyTesseract](https://github.com/SwiftyTesseract/SwiftyTesseract) (with support for v4.0.1 via custom CocoaPods) and Apple's Vision framework.

## Features

*   Perform OCR on images to extract text.
*   Support for multiple OCR engines: Tesseract (iOS/Android), Apple Vision (iOS).
*   Configurable OCR options (language, engine mode, page segmentation mode, etc.) using `OCRConfig`.
*   Supports the latest Dart and Android SDKs.
*   Includes a custom CocoaPods setup to enable using SwiftyTesseract 4.0.1 on iOS.

## Getting Started

### 1. Add Dependency

Add `tesseract_ocr` to your `pubspec.yaml`:

```yaml
dependencies:
  tesseract_ocr: ^<latest_version> # Replace <latest_version> with the current version
```

Then run `flutter pub get`.

### 2. Add Trained Data (Required for Tesseract Engine)

For the Tesseract engine to work, you need to include language trained data files (`.traineddata`) and a configuration file (`tessdata_config.json`) in your Flutter app's assets.

1.  **Create `assets` and `assets/tessdata` folders** in the root of your Flutter project.
2.  **Download Trained Data:** Get the necessary `.traineddata` files for the languages you need from the [Tesseract `tessdata`](https://github.com/tesseract-ocr/tessdata), [`tessdata_best`](https://github.com/tesseract-ocr/tessdata_best), or [`tessdata_fast`](https://github.com/tesseract-ocr/tessdata_fast) repositories. Place them inside your `assets/tessdata` folder. For English, you'll typically need `eng.traineddata`.
3.  **Create `tessdata_config.json`:** Create a file named `tessdata_config.json` directly inside your `assets` folder (not in `assets/tessdata`). This file should list all the `.traineddata` files present in your `assets/tessdata` folder.

    Example `assets/tessdata_config.json`:

    ```json
    {
      "files": [
        "eng.traineddata",
        "fas.traineddata",
        "urd.traineddata"
        // Add all other .traineddata filenames here
      ]
    }
    ```
4.  **Declare Assets in `pubspec.yaml`:** Add your `assets` and `assets/tessdata` directories to the `assets` section of your `pubspec.yaml`:

    ```yaml
    flutter:
      assets:
        - assets/tessdata_config.json
        - assets/tessdata/
    ```
    Run `flutter pub get` again.

The plugin will automatically copy these trained data files to the application's documents directory on the first run if they are not already present.

## iOS Specific Setup (SwiftyTesseract 4.0.1 via Custom CocoaPods)

SwiftyTesseract 4.0.x uses Swift Package Manager and removed CocoaPods support. To allow this plugin to use SwiftyTesseract 4.0.1 via CocoaPods, a custom setup is provided.

**Important:** This requires manual steps in your iOS project.

1.  **Download `libtesseract.xcframework`**: SwiftyTesseract 4.0.1 depends on `libtesseract` version 0.2.0, which is also not available on CocoaPods. You need to download the pre-built binary framework. Get `libtesseract.xcframework.zip` for version `0.2.0` from the [libtesseract GitHub Releases page](https://github.com/SwiftyTesseract/libtesseract/releases/tag/0.2.0).
2.  **Extract and Place `libtesseract.xcframework`**: Unzip the downloaded file. Place the resulting `libtesseract.xcframework` folder directly into your Flutter app's **`ios`** directory (the same directory where your main `Podfile` is located).

    Your app's `ios` directory structure should look like this:

    ```
    your_flutter_app/ios/
    ├── Runner.xcodeproj
    ├── Runner.xcworkspace
    ├── Podfile         <-- Your main Podfile
    ├── libtesseract.xcframework  <-- Place the extracted folder here
    └── ... (other iOS files)
    ```
3.  **Configure Your App's Podfile**: In your Flutter app's `ios/Podfile`, you need to reference the custom podspecs provided within the `tesseract_ocr` plugin using the `:path` option.

    Locate your `target 'Runner'` block and add the following lines:

    ```ruby
    # In your main Flutter app's Podfile (e.g., your_flutter_app/ios/Podfile)

    # ... other Podfile content ...

    target 'Runner' do
      use_frameworks!
      use_modular_headers!

      # This line should already be here if you added the plugin via pubspec.yaml
      pod 'tesseract_ocr', :path => '../.symlinks/plugins/tesseract_ocr/'

      # Add the custom SwiftyTesseract401 and libtesseract pods
      # These paths are relative from YOUR app's ios directory to the plugin's ios directory
      # Adjust the '../../.symlinks/plugins/tesseract_ocr/ios' path if necessary
      pod 'SwiftyTesseract401', :path => '../../.symlinks/plugins/tesseract_ocr/ios'
      pod 'libtesseract', :path => '../../.symlinks/plugins/tesseract_ocr/ios'


      # flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__)) # Keep this line

    end

    # ... other Podfile content (e.g., post_install hook) ...
    ```

    **Note:** The `:path` value `../../.symlinks/plugins/tesseract_ocr/ios` is the standard path from your app's `ios` directory to a plugin's `ios` directory when using Flutter. If your project structure is different, you may need to adjust this path.
4.  **Install Pods**: Navigate to your `ios` directory in the terminal and run `pod install`:

    ```bash
    cd your_flutter_app/ios
    pod install
    ```

### Android SDK Support

The plugin is configured to compile against the latest Android SDK (API 35) and has a minimum SDK version of 16, providing broad compatibility.

## Usage

Import the package:

```dart
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
```

To perform OCR, use the `TesseractOcr.extractText` method. You can pass an optional `OCRConfig` object to specify the engine and other options.

```dart
Future<void> _performOcr(String imagePath) async {
  try {
    // Default usage (uses OCREngine.defaultEngine, language 'eng')
    // String extractedText = await TesseractOcr.extractText(imagePath);

    // Example: Using Tesseract engine with a specific language
    final tesseractConfig = OCRConfig(
      language: 'eng', // Must match a .traineddata file in assets/tessdata
      engine: OCREngine.tesseract,
      // Optional Tesseract options:
      // options: {
      //   TesseractConfig.preserveInterwordSpaces: '1',
      //   TesseractConfig.pageSegMode: PageSegmentationMode.autoOsd,
      //   TesseractConfig.debugFile: '/path/to/debug.log', // Example option
      // },
    );
    String extractedTextTesseract = await TesseractOcr.extractText(
      imagePath,
      config: tesseractConfig,
    );
    print('Extracted Text (Tesseract): $extractedTextTesseract');

    // Example: Using Apple Vision engine (iOS only)
    final visionConfig = OCRConfig(
      engine: OCREngine.vision,
      language: 'eng', // Vision engine may also use language hint
    );
     // Check if running on iOS before using Vision
    if (Platform.isIOS) {
      String extractedTextVision = await TesseractOcr.extractText(
        imagePath,
        config: visionConfig,
      );
      print('Extracted Text (Vision): $extractedTextVision');
    }


  } catch (e) {
    print('Error performing OCR: $e');
  }
}
```

### `OCRConfig`

The `OCRConfig` class allows detailed configuration of the OCR process:

*   `language` (String): The language code (e.g., 'eng', 'fas'). Required for the Tesseract engine, usually corresponds to the `.traineddata` file prefix. Can be used as a hint for the Vision engine. Defaults to 'eng'.
*   `engine` (`OCREngine`): The OCR engine to use (`OCREngine.vision`, `OCREngine.tesseract`, or `OCREngine.defaultEngine`). Defaults to `OCREngine.defaultEngine` (Vision on iOS, Tesseract on Android).
*   `tessDataPath` (String?): **Internal Use.** The plugin automatically handles loading tessdata from assets; you typically don't need to set this.
*   `options` (Map<String, dynamic>?): A map of additional configuration options.
    *   For the **Tesseract** engine, these are passed directly to the Tesseract API. Use keys from `TesseractConfig` or any valid Tesseract configuration variable name (e.g., `'preserve_interword_spaces'`, `'tessedit_pageseg_mode'`). Values should be strings.
    *   For the **Vision** engine (iOS), limited options might be supported depending on the native implementation (currently, primarily language hint via `language`).

See `ocr_engine_config.dart` for the `OCREngine`, `TesseractConfig`, and `PageSegmentationMode` enums and classes.

## Example

Check the `example` directory for a complete Flutter app demonstrating how to use the plugin, select images, choose the OCR engine, and display results.