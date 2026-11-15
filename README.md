# Tesseract OCR for Flutter

A Flutter plugin that provides Optical Character Recognition (OCR) capabilities using Tesseract (v4.x) and Apple Vision (iOS).

This plugin utilizes:

- **Android:** [Tesseract4Android](https://github.com/adaptech-cz/Tesseract4Android/)
- **iOS:** [SwiftyTesseract](https://github.com/SwiftyTesseract/SwiftyTesseract) (with support for v4.0.1 via custom CocoaPods) and Apple's Vision framework.
- **Web:** [Tesseract.js](https://www.npmjs.com/package/tesseract.js) (`v6.0.1` WebAssembly) using the app's bundled `.traineddata` assets.
- **macOS:** [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) via Swift Package Manager using the bundled `.traineddata` assets.
- **Linux:** System [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) and Leptonica libraries via C++ CMake plugin.
- **Windows:** [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) and Leptonica libraries via C++ CMake plugin (vcpkg, MSYS2, or the UB-Mannheim installer).

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
- Support for multiple OCR engines: Tesseract (Android, iOS, macOS, Linux, Windows, and Web), Apple Vision (iOS only).
- Configurable OCR options (language, engine mode, page segmentation mode, etc.) using `OCRConfig`.
- Supports the latest Dart and Android SDKs.
- **Swift Package Manager (SPM) support** for iOS and macOS (recommended)
- **Linux support** via system tesseract library
- **Windows support** via a C++ plugin that links Tesseract and bundles its DLLs

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
- A release build only carries the assets your `pubspec.yaml` declares. The plugin
  refuses to start recognition with an incomplete tessdata set instead of
  returning garbage — see the error codes below.

## Common Issues and Solutions

### "Data path must not be null!" Error

This error typically occurs when:

- The tessdata files are not properly loaded from assets
- The `tessdata_config.json` file is missing or incorrectly formatted
- Asset paths in `pubspec.yaml` are not correctly configured

**Solution:** Follow the exact directory structure and configuration shown above.

### `tessdata-config-invalid` / `tessdata-asset-invalid` Errors

`extractText` now refuses to run when the tessdata set it would hand to Tesseract
is incomplete, instead of letting the engine initialize on an empty or partial
directory and return garbage. Both are `PlatformException`s whose message names
the offending asset and the `pubspec.yaml` declaration that carries it.

- `tessdata-config-invalid` — `assets/tessdata_config.json` is not valid JSON, is
  not an object, does not carry a non-empty `files` array, or lists an entry that
  is not a flat `.traineddata` file name (a path such as `sub/eng.traineddata`,
  or an entry that is not a string, is a config mistake). It must be an object
  with a non-empty `files` array: `{"files": ["eng.traineddata"]}`.
- `tessdata-asset-invalid` — `assets/tessdata_config.json` is not carried by the
  bundle, or a `.traineddata` listed in that config is not carried by the bundle,
  is empty, or differs from the file already on disk (missing, truncated, or
  replaced by another build) and cannot be rewritten.

**Solution:**

1. Declare the config and every traineddata it lists under `flutter: assets:`
   in your app's `pubspec.yaml` — individually, if the directory form does not
   pick them up:

   ```yaml
   assets:
     - assets/tessdata_config.json
     - assets/tessdata/eng.traineddata
   ```

2. Run `flutter clean && flutter pub get`, then rebuild. Release builds only
   carry declared assets, so an install that predates a declaration keeps the
   old, empty tessdata directory — the copy is refreshed whenever the asset's
   contents differ from the file already on disk, so a same-size file from an
   older build is replaced too. Assets are read once per app run, so the copy
   check costs one read per declared file rather than one per `extractText` call.

### "Unable to load asset" Error

This happens when Flutter cannot find the specified asset files.

**Solution:**

1. Verify file names match exactly between `tessdata_config.json` and actual files
2. Ensure proper asset declarations in `pubspec.yaml`
3. Try running `flutter clean` and `flutter pub get`

### Path Duplication Issues (M1 Macs)

Some users on M1 Macs may see paths like `assets/tessdata/assets/tessdata/file.traineddata`.

**Solution:** The plugin automatically handles this, but ensure you're using the latest version.

## iOS Specific Setup (Swift Package Manager - Recommended)

Starting with version 0.5.2+, this plugin uses **Swift Package Manager (SPM)** for iOS, which is the recommended approach going forward.

### SPM Installation (Recommended)

The plugin automatically integrates with SPM when you add it via `pubspec.yaml`. No additional configuration is required.

**Requirements:**
- iOS 11.0 or later
- Xcode 12.0 or later
- Flutter 3.19.0 or later

The plugin uses [SwiftyTesseract](https://github.com/SwiftyTesseract/SwiftyTesseract) 4.0.1+ which is automatically fetched and built via SPM.

### Legacy CocoaPods Setup (Deprecated)

> **⚠️ DEPRECATED:** The CocoaPods setup is deprecated and will be removed in a future version. Please migrate to SPM.

For existing projects using CocoaPods, the legacy setup is still available but requires manual steps:

1.  **Download `libtesseract.xcframework`**: SwiftyTesseract 4.0.1 depends on `libtesseract` version 0.2.0, which is also not available on CocoaPods. You need to download the pre-built binary framework. Get `libtesseract-0.2.0.xcframework.zip` from the [libtesseract GitHub Releases page](https://github.com/SwiftyTesseract/libtesseract/releases/tag/0.2.0).
2.  **Extract and Place `libtesseract.xcframework`**: Unzip the downloaded file. Place the resulting `libtesseract.xcframework` folder directly into the **plugin's** `ios` directory — the directory that contains `libtesseract.podspec` — **not** into your app's `ios` directory.

    The plugin's pod is consumed by `:path` from its own `ios` directory, and `libtesseract.podspec` resolves the xcframework relative to itself. So the binary must sit beside the podspec:

    ```
    .symlinks/plugins/tesseract_ocr/ios/
    ├── libtesseract.podspec          <-- The podspec that consumes it
    ├── libtesseract.xcframework      <-- Place the extracted folder here
    ├── SwiftyTesseract401.podspec
    └── tesseract_ocr.podspec
    ```

    Your app's own `ios` directory keeps only the usual Flutter files (`Runner.xcodeproj`, `Runner.xcworkspace`, `Podfile`) — the xcframework does not belong there.

3.  **Configure Your App's Podfile**: In your Flutter app's `ios/Podfile`, you need to reference the custom podspecs provided within the `tesseract_ocr` plugin: `SwiftyTesseract401` by `:podspec`, `libtesseract` by `:path`. No `EXCLUDED_ARCHS` entry is needed — the arm64 Apple Silicon simulator slice builds on its own.

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
      pod 'SwiftyTesseract401', :podspec => '../../.symlinks/plugins/tesseract_ocr/ios/SwiftyTesseract401.podspec'
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

macOS support uses the **Tesseract** engine via **Swift Package Manager (SPM)**. Apple Vision (`OCREngine.vision`) remains iOS-only and is not supported on macOS. Language `.traineddata` files ship in your Flutter app's `assets/tessdata/` directory just like on mobile—no separate per-machine language setup is required for English (`eng`) or other bundled trained data.

### Prerequisites

1. **Flutter macOS Desktop Support**: Ensure Flutter macOS desktop is enabled (`flutter config --enable-macos-desktop`) along with Xcode 12.0 or later.
2. **SPM Integration**: The plugin automatically integrates with SPM when added via `pubspec.yaml`. No additional configuration is required.
3. **App Sandbox Configuration**: If your macOS app uses App Sandbox, you must disable it in `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:
   ```xml
   <key>com.apple.security.app-sandbox</key>
   <false/>
   ```
   (This is already configured in `example/macos/Runner/`.)

## Linux Setup & Prerequisites

Linux support uses the **system Tesseract library** installed via your distribution's package manager.

### Prerequisites

1. **Flutter Linux Desktop Support**: Ensure Flutter Linux desktop is enabled (`flutter config --enable-linux-desktop`).
2. **Install Tesseract and Leptonica**:

   **Ubuntu/Debian:**
   ```bash
   sudo apt-get install libtesseract-dev libleptonica-dev
   ```

   **Fedora/RHEL:**
   ```bash
   sudo yum install tesseract-devel leptonica-devel
   ```

   **Arch Linux:**
   ```bash
   sudo pacman -S tesseract leptonica
   ```

3. **Verify Installation**:
   ```bash
   tesseract --version
   ```

The plugin uses the system Tesseract library directly via C++ interop, providing native performance without bundled binaries.

## Windows Setup & Prerequisites

Windows support uses the same **Tesseract engine and `tesseract_ocr` method channel** as Linux, implemented as a C++ CMake plugin. `OCREngine.vision` stays iOS-only and is rejected on Windows; every other engine value runs on Tesseract.

### Prerequisites

1. **Flutter Windows Desktop Support**: Enable it with `flutter config --enable-windows-desktop`. You also need Visual Studio 2022 with the "Desktop development with C++" workload, which provides MSVC and CMake 3.14 or later.
2. **Install Tesseract and Leptonica *with their development files***. The plugin links both libraries and copies their DLLs next to your executable, so a runtime-only install is not enough — it needs `include/tesseract/capi.h` and the import libraries. Any one of these works:

   **vcpkg:**
   ```powershell
   vcpkg install tesseract
   ```

   **MSYS2:**
   ```bash
   pacman -S mingw-w64-x86_64-tesseract
   ```

   **UB-Mannheim installer:** enable "Install development files" so `include/` and `lib/` land in the prefix, then point the configure step at it:
   ```powershell
   $env:TESSERACT_ROOT = "C:\Program Files\Tesseract-OCR"
   flutter build windows
   ```
   The plugin also probes the standard prefixes (`%ProgramFiles%\Tesseract-OCR`, the 32-bit one, and the per-user install), so an installer in the default location needs no configuration at all.

3. **Trained data**: `eng` ships with the installer. Other languages are picked up from the Tesseract prefix's `tessdata/`, or from the `assets/tessdata/` set the plugin copies into the app's documents directory like every other platform, or from a path you pass as `OCRConfig(tessDataPath: ...)`. When no path is supplied the plugin also honours `TESSDATA_PREFIX`.

If Tesseract cannot be found, the build stops with the exact packages to install rather than producing a plugin DLL that would fail to load at runtime.

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
- `options` (Map<String, dynamic>?): A map of additional configuration options. Which keys each platform honours:
  - **Android, macOS, Linux and Web (Tesseract engine):** passed to the Tesseract engine. Use keys from `TesseractConfig` or any valid Tesseract configuration variable name (e.g., `'preserve_interword_spaces'`, `'tessedit_pageseg_mode'`). Values should be strings. `tessedit_pageseg_mode` selects the page segmentation mode and `tessedit_ocr_engine_mode` the engine mode; every other key is set as a Tesseract variable.
  - **iOS (Vision engine):** Vision has no Tesseract variable set. `TesseractConfig.recognitionLevel` (`'fast'` or `'accurate'`, default `'accurate'`) and `TesseractConfig.usesLanguageCorrection` (`true` or `false`, default `true`) are honoured; any other key is logged as ignored rather than silently accepted.
  - A value a platform cannot apply is dropped and logged, never guessed: an unsupported page segmentation mode keeps the engine default, and an unparsable boolean keeps Vision's default.

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

### Running the Linux Example App

```bash
cd example
flutter pub get
flutter run -d linux
```

### Running the Linux Integration Test

```bash
cd example
flutter test integration_test/tesseract_ocr_linux_test.dart -d linux
```

### Running the Linux Integration Test in Docker (headless)

```bash
docker build -f example/docker/linux.Dockerfile -t tesseract-ocr-linux-test .
docker run --rm tesseract-ocr-linux-test
```

## Web Setup (Tesseract.js)

Web support uses [tesseract.js](https://github.com/naptha/tesseract.js) compiled to WebAssembly. The library is loaded dynamically from a CDN on first use.

### Content Security Policy (CSP)

If your app uses a strict Content Security Policy, you must allowlist the jsDelivr CDN in your `web/index.html`:

```html
<meta http-equiv="Content-Security-Policy" content="script-src 'self' https://cdn.jsdelivr.net;">
```

Alternatively, you can self-host `tesseract.min.js` by including it in your `web/index.html` before the Flutter bootstrap script.
