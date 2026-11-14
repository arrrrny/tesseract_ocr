# Using SwiftyTesseract 4.0.1 via Custom CocoaPods Setup

This document explains how to configure your iOS project to use SwiftyTesseract version 4.0.1 with the `tesseract_ocr` Flutter plugin when integrating via CocoaPods.

SwiftyTesseract versions 4.0.0 and above dropped support for CocoaPods in favor of Swift Package Manager. However, to allow users of this plugin to utilize the features of 4.0.1 while still using CocoaPods, a custom podspec setup has been created within this plugin.

This custom setup involves:
1.  `tesseract_ocr.podspec` now depends on a custom pod named `SwiftyTesseract401`.
2.  A local podspec, `SwiftyTesseract401.podspec`, is provided within the plugin's `ios` directory. This podspec points directly to the SwiftyTesseract 4.0.1 tag on GitHub.
3.  SwiftyTesseract 4.0.1 itself depends on `libtesseract`, which is also not available on CocoaPods. A local podspec, `libtesseract.podspec`, is provided to make the `libtesseract.xcframework` available via CocoaPods.

**Important:** For this custom CocoaPods setup to work, you **must** manually obtain and include the `libtesseract.xcframework` **in the plugin's `ios` directory** — the directory that contains `libtesseract.podspec`. It does not go in your app's `ios` directory.

## Prerequisites

1.  **Download `libtesseract.xcframework`**: Download the `libtesseract-0.2.0.xcframework.zip` file for version `0.2.0` from the [libtesseract GitHub Releases page](https://github.com/SwiftyTesseract/libtesseract/releases/tag/0.2.0).
2.  **Extract and Place**: Unzip the downloaded file and place the resulting `libtesseract.xcframework` folder into the **plugin's** `ios` directory, beside `libtesseract.podspec` — not into your Flutter app's `ios` directory.

    The pod is consumed by `:path` from the plugin's `ios` directory and the podspec resolves the xcframework relative to itself (`__dir__`), so this is the only location that works:

    ```
    .symlinks/plugins/tesseract_ocr/ios/
    ├── libtesseract.podspec          <-- The podspec that consumes it
    ├── libtesseract.xcframework      <-- Place the extracted folder here
    ├── SwiftyTesseract401.podspec
    └── tesseract_ocr.podspec
    ```

    If the binary is missing, `pod install` now fails loudly (the podspec raises) instead of silently dropping the vendored framework and failing later with a link error or `Couldn't find module`.

## Configure Your Podfile

In your Flutter app's `ios/Podfile`, you need to reference the custom `SwiftyTesseract401.podspec` and `libtesseract.podspec` provided by the `tesseract_ocr` plugin. `SwiftyTesseract401` is referenced by `:podspec` (CocoaPods fetches the upstream 4.0.1 sources named by the podspec's `source`); `libtesseract` is referenced by `:path`.

Locate your `target 'Runner'` block and add the following lines:

```ruby
# Your main Podfile in your Flutter app (e.g., your_flutter_app/ios/Podfile)

# ... other Podfile content ...

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  # Reference the tesseract_ocr plugin's pod
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

**Note:** The `../../.symlinks/plugins/tesseract_ocr/ios` path is the standard path from your app's `ios` directory to a plugin's `ios` directory when using Flutter. If your project structure is different, you may need to adjust this path.

No `EXCLUDED_ARCHS` entry is needed: the CocoaPods path builds the arm64 Apple Silicon simulator slice on its own. Do not add one — excluding `arm64` for the simulator only hides the arm64 module this setup is supposed to provide.

## Install Pods

After modifying your Podfile, navigate to your `ios` directory in the terminal and run `pod install`:

```bash
cd your_flutter_app/ios
pod install
```

CocoaPods should now be able to find and install the `SwiftyTesseract401` and `libtesseract` pods using the provided custom podspecs and the `libtesseract.xcframework` located in the plugin's `ios` directory.

## Important Considerations

*   **`libtesseract.xcframework` Distribution**: Since the `libtesseract.podspec` references the xcframework by a local file path relative to itself, anyone who clones the plugin's repository and builds an app against the CocoaPods path will need `libtesseract.xcframework` present in the plugin's `ios` directory (`<plugin>/ios/libtesseract.xcframework`). The binary is not committed to this repository — obtain it from the releases page above, or consider adding it to your own checkout (potentially using Git LFS if it's large).
*   **Plugin Users**: If you are the author of the `tesseract_ocr` plugin, users integrating your plugin into *their* apps via CocoaPods will need to place `libtesseract.xcframework` in the **plugin's** `ios` directory (the `.symlinks/plugins/tesseract_ocr/ios` path above), not in their app's own `ios` directory. The custom podspecs are part of your plugin's distribution, but the `libtesseract.xcframework` itself is not automatically included by CocoaPods when using `:path`.