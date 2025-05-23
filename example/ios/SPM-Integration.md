# Installing SwiftyTesseract via Swift Package Manager (SPM) in Xcode

Since SwiftyTesseract 4.x only supports SPM, you need to add it directly in Xcode:

## Steps to Add SwiftyTesseract in Xcode:

1. Open your Flutter project's iOS folder in Xcode:
   ```
   open ios/Runner.xcworkspace
   ```

2. In Xcode, go to `File` > `Add Packages...`

3. In the search bar at the top right, paste the SwiftyTesseract repository URL:
   ```
   https://github.com/SwiftyTesseract/SwiftyTesseract.git
   ```

4. Select "Up to Next Major Version" with "4.0.0" as the minimum version

5. Click `Add Package`

6. Make sure "Runner" target is selected and click `Add Package`

## Setup tessdata folder:

1. Download language training data from:
   - [tessdata](https://github.com/tesseract-ocr/tessdata)
   - [tessdata_best](https://github.com/tesseract-ocr/tessdata_best)
   - [tessdata_fast](https://github.com/tesseract-ocr/tessdata_fast)

2. Create a tessdata folder in your iOS project's assets

3. Add your language files (e.g. eng.traineddata) to this folder

4. Update Info.plist to include:
   ```
   <key>SwiftyTesseract</key>
   <dict>
       <key>tessDataPath</key>
       <string>$(SRCROOT)/Runner/tessdata</string>
   </dict>
   ```

## Update SwiftTesseractOcrPlugin.swift:

Update your plugin implementation to use SwiftyTesseract 4.x API directly.

## Important Notes:

- When submitting to App Store Connect, you'll need to remove libtesseract.framework
- Add this script to your build phases:
  ```
  if [ "${CONFIGURATION}" = "Release" ]; then
    echo "Removing libtesseract.framework for App Store submission"
    rm -rf "${TARGET_BUILD_DIR}/${PRODUCT_NAME}.app/Frameworks/libtesseract.framework"
  fi
  ```