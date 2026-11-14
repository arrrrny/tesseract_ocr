# Tesseract OCR for Flutter

A Flutter plugin that provides Optical Character Recognition (OCR) capabilities using Tesseract (v4.x) and Apple Vision (iOS).

This plugin utilizes:

- **Android:** [Tesseract4Android](https://github.com/adaptech-cz/Tesseract4Android/)
- **iOS:** [SwiftyTesseract](https://github.com/SwiftyTesseract/SwiftyTesseract) (with support for v4.0.1 via custom CocoaPods) and Apple's Vision framework.
- **Web:** [Tesseract.js](https://www.npmjs.com/package/tesseract.js) (`v6.0.1` WebAssembly) using the app's bundled `.traineddata` assets.
- **macOS:** [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) CLI (`brew install tesseract`) using the bundled `.traineddata` assets.

<!-- ZURAFFA-LAUNCH-PROMO (valid until Dec 1, 2026) -->
## 🦒 Zuraffa Browser — Launch Offer

<div align="center">
  <a href="https://zuraffa.com"><img src="https://zuraffa.com/img/zuraffa-browser-home.jpg" alt="Zuraffa Browser — 10 Browsers. One window." width="720"></a>
</div>

From the makers of this plugin: **[Zuraffa Browser](https://zuraffa.com)** — the multi-tasking browser for AI agents & humans — is live on the **[Mac App Store](https://apps.apple.com/app/id6811352058)**.

🎁 **Launch offer: 6 months free with code `ZURAFFA`** — no credit card, no subscription, no payment. Redeem in-app until **Dec 1, 2026**.

[**Download Zuraffa Browser →**](https://apps.apple.com/app/id6811352058)


## Features

- Perform OCR on images to extract text.
- Support for multiple OCR engines: Tesseract (Android, iOS, macOS, and Web), Apple Vision (iOS only).
- Configurable OCR options (language, engine mode, page segmentation mode, etc.) using `OCRConfig`.
- Supports the latest Dart and Android SDKs.
- Includes a custom CocoaPods setup to enable using SwiftyTesseract 4.0.1 on iOS.

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

**Note on Asset Loading Issues:** If you encounter asset loading errors or "Data path must not be null!" errors, ensure your setup follows these exact requirements:

1. **Directory Structure:**

   ```
   your_project/
   ├── assets/
   │   ├── tessdata/
   │   │   ├── eng.traineddata
   │   │   └── [other language files]
   │   └── tessdata_config.json
   └── pubspec.yaml
   ```

2. **pubspec.yaml assets section:**

   ```yaml
   flutter:
     assets:
       - assets/
       - assets/tessdata/
   ```

3. **tessdata_config.json content:**
   ```json
   {
     "files": ["eng.traineddata"]
   }
   ```

**Troubleshooting:**

- Ensure `.traineddata` files are in `assets/tessdata/` directory
- Verify all language files listed in `tessdata_config.json` actually exist
- Try adding individual file entries in pubspec.yaml if assets fail to load:
  ```yaml
  assets:
    - assets/tessdata_config.json
    - assets/tessdata/eng.traineddata
  ```

## Common Issues and Solutions

### "Data path must not be null!" Error

This error typically occurs when:

- The tessdata files are not properly loaded from assets
- The `tessdata_config.json` file is missing or incorrectly formatted
- Asset paths in `pubspec.yaml` are not correctly configured

**Solution:** Follow the exact directory structure and configuration shown above.

### "Unable to load asset" Error

This happens when Flutter cannot find the specified asset files.

**Solution:**

1. Verify file names match exactly between `tessdata_config.json` and actual files
2. Ensure proper asset declarations in `pubspec.yaml`
3. Try running `flutter clean` and `flutter pub get`

### Path Duplication Issues (M1 Macs)

Some users on M1 Macs may see paths like `assets/tessdata/assets/tessdata/file.traineddata`.

**Solution:** The plugin automatically handles this, but ensure you're using the latest version.

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

## Web Setup (Tesseract.js)

Web support uses [Tesseract.js](https://www.npmjs.com/package/tesseract.js) (`v6.0.1`) compiled to WebAssembly (`OCREngine.tesseract` / `OCREngine.defaultEngine`). Apple Vision (`OCREngine.vision`) remains iOS-only and throws an `UnsupportedError` on Web.

- **Automatic CDN Loading:** By default, the Web plugin dynamically loads `tesseract.min.js` (`v6.0.1`) from jsDelivr on first use when `window.Tesseract` is not already present.
- **Self-Hosting / Offline / Strict CSP:** If you prefer to self-host `tesseract.js` or restrict external scripts via CSP, include `<script src="...tesseract.min.js"></script>` in your `web/index.html` before `flutter_bootstrap.js`.
- **Language Data:** Bundled `assets/tessdata/*.traineddata` files listed in `assets/tessdata_config.json` are served directly from Flutter Web's asset bundle (`gzip: false`), supporting both LSTM (`eng.traineddata`, `financial.traineddata`) and legacy (`OCRB.traineddata`) models. You can also supply a custom `OCRConfig(tessDataPath: ...)` URL.

## macOS Setup & Prerequisites

macOS support uses the **Tesseract** engine (`OCREngine.tesseract` / `OCREngine.defaultEngine`). Apple Vision (`OCREngine.vision`) remains iOS-only and is not supported on macOS. Language `.traineddata` files ship in your Flutter app's `assets/tessdata/` directory just like on mobile—no separate per-machine language setup is required for English (`eng`) or other bundled trained data.

### Prerequisites

1. **Flutter macOS Desktop Support**: Ensure Flutter macOS desktop is enabled (`flutter config --enable-macos-desktop`) along with Xcode and CocoaPods.
2. **Install Tesseract via Homebrew**:
   ```bash
   brew install tesseract
   ```
   The plugin automatically discovers `tesseract` in `/opt/homebrew/bin/tesseract` (Apple Silicon), `/usr/local/bin/tesseract` (Intel), `/opt/local/bin/tesseract`, `/usr/bin/tesseract`, `PATH`, or via the `TESSERACT_PATH` environment variable.
3. **Disable App Sandbox in Your macOS Runner Entitlements**: Because the macOS plugin invokes the installed `tesseract` binary as a subprocess, macOS App Sandbox must be disabled in `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:
   ```xml
   <key>com.apple.security.app-sandbox</key>
   <false/>
   ```
   (This is already configured in `example/macos/Runner/`.)

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

- `language` (String): The language code (e.g., 'eng', 'fas'). Required for the Tesseract engine, usually corresponds to the `.traineddata` file prefix. Can be used as a hint for the Vision engine. Defaults to 'eng'.
- `engine` (`OCREngine`): The OCR engine to use (`OCREngine.vision`, `OCREngine.tesseract`, or `OCREngine.defaultEngine`). Defaults to `OCREngine.defaultEngine` (Vision on iOS; Tesseract on Android, macOS, and Web).
- `tessDataPath` (String?): **Internal Use.** The plugin automatically handles loading tessdata from assets; you typically don't need to set this.
- `options` (Map<String, dynamic>?): A map of additional configuration options.
  - For the **Tesseract** engine, these are passed directly to the Tesseract API. Use keys from `TesseractConfig` or any valid Tesseract configuration variable name (e.g., `'preserve_interword_spaces'`, `'tessedit_pageseg_mode'`). Values should be strings.
  - For the **Vision** engine (iOS), limited options might be supported depending on the native implementation (currently, primarily language hint via `language`).

See `ocr_engine_config.dart` for the `OCREngine`, `TesseractConfig`, and `PageSegmentationMode` enums and classes.

## Example

Check the `example` directory for a complete Flutter app demonstrating how to use the plugin, select images, choose the OCR engine, and display results.

### Running the Web Example App

```bash
cd example
flutter pub get
flutter run -d chrome
```

### Running the Web Integration Test

```bash
cd example
flutter test integration_test/tesseract_ocr_web_test.dart -d chrome
```

### Running the macOS Example App

```bash
cd example
flutter pub get
flutter run -d macos
```

### Running the macOS Integration Test

```bash
cd example
flutter test integration_test/tesseract_ocr_macos_test.dart -d macos
```
