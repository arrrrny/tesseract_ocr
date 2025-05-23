# Using SwiftyTesseract 4.0.1 via Custom CocoaPods Setup

This document explains how to configure your iOS project to use SwiftyTesseract version 4.0.1 with the `tesseract_ocr` Flutter plugin when integrating via CocoaPods.

SwiftyTesseract versions 4.0.0 and above dropped support for CocoaPods in favor of Swift Package Manager. However, to allow users of this plugin to utilize the features of 4.0.1 while still using CocoaPods, a custom podspec setup has been created within this plugin.

This custom setup involves:
1.  `tesseract_ocr.podspec` now depends on a custom pod named `SwiftyTesseract401`.
2.  A local podspec, `SwiftyTesseract401.podspec`, is provided within the plugin's `ios` directory. This podspec points directly to the SwiftyTesseract 4.0.1 tag on GitHub.
3.  SwiftyTesseract 4.0.1 itself depends on `libtesseract`, which is also not available on CocoaPods. A local podspec, `libtesseract.podspec`, is provided to make the `libtesseract.xcframework` available via CocoaPods.

**Important:** For this custom CocoaPods setup to work, you **must** manually obtain and include the `libtesseract.xcframework` in your project.

## Prerequisites

1.  **Download `libtesseract.xcframework`**: Download the `libtesseract.xcframework.zip` file for version `0.2.0` from the [libtesseract GitHub Releases page](https://github.com/SwiftyTesseract/libtesseract/releases/tag/0.2.0).
2.  **Extract and Place**: Unzip the downloaded file and place the resulting `libtesseract.xcframework` folder directly into your Flutter app's `ios` directory (the same directory where your main `Podfile` is located).

    Your `ios` directory structure should look something like this:

    ```
    your_flutter_app/ios/
    ├── Runner.xcodeproj
    ├── Runner.xcworkspace
    ├── Podfile         <-- Your main Podfile
    ├── libtesseract.xcframework  <-- Place the extracted folder here
    └── ... (other iOS files)
    ```

## Configure Your Podfile

In your Flutter app's `ios/Podfile`, you need to reference the custom `SwiftyTesseract401.podspec` and `libtesseract.podspec` provided by the `tesseract_ocr` plugin using the `:path` option.

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
  pod 'SwiftyTesseract401', :path => '../../.symlinks/plugins/tesseract_ocr/ios'
  pod 'libtesseract', :path => '../../.symlinks/plugins/tesseract_ocr/ios'


  # flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__)) # Keep this line

end

# ... other Podfile content (e.g., post_install hook) ...
```

**Note:** The `:path` value `../../.symlinks/plugins/tesseract_ocr/ios` is the standard path from your app's `ios` directory to a plugin's `ios` directory when using Flutter. If your project structure is different, you may need to adjust this path.

## Install Pods

After modifying your Podfile, navigate to your `ios` directory in the terminal and run `pod install`:

```bash
cd your_flutter_app/ios
pod install
```

CocoaPods should now be able to find and install the `SwiftyTesseract401` and `libtesseract` pods using the provided custom podspecs and the `libtesseract.xcframework` located in your `ios` directory.

## Important Considerations

*   **`libtesseract.xcframework` Distribution**: Since the `libtesseract.podspec` references the xcframework by a local file path, anyone who clones your repository and builds the app will need to also have `libtesseract.xcframework` in the correct location (`your_flutter_app/ios/libtesseract.xcframework`). You may need to consider adding this xcframework to your repository (potentially using Git LFS if it's large) or providing separate instructions for obtaining it.
*   **Plugin Users**: If you are the author of the `tesseract_ocr` plugin, users integrating your plugin into *their* apps via CocoaPods will need to follow these steps in *their* app's `ios` directory. The custom podspecs are now part of your plugin's distribution, but the `libtesseract.xcframework` itself is not automatically included by CocoaPods when using `:path`.