#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tesseract_ocr.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'tesseract_ocr'
  s.version          = '0.6.0'
  s.summary          = 'Tesseract OCR 4 Flutter'
  s.description      = <<-DESC
Tesseract 4 adds a new neural net (LSTM) based OCR engine which is focused on line recognition. It has unicode (UTF-8) support, and can recognize more than 100 languages.
                       DESC
  s.homepage         = 'https://github.com/arrrrny/tesseract_ocr'
  s.license          = { :file => '../LICENSE', :type => 'BSD' }
  s.author           = { 'Ahmet TOK' => 'arny@paratoner.io' }
  s.source           = { :path => '.' }

  # macOS compiles the SAME shared Swift source as iOS (Sources/tesseract_ocr/),
  # plus a one-method ObjC shim that carries the `TesseractOcrPlugin` name the
  # generated plugin registrant imports. The old macOS-only
  # `tesseract_ocr/Sources/.../TesseractOcrPlugin.swift` drove the `tesseract`
  # command-line binary through Foundation.Process; it is gone, so macOS runs the
  # in-process Tesseract engine with the same tessData/options contract as iOS.
  s.source_files     = 'Classes/*.{h,m,mm}', '../Sources/tesseract_ocr/*.swift'
  s.public_header_files = 'Classes/**/*.h'

  s.resource_bundles = {
    'tesseract_ocr_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }

  s.dependency 'FlutterMacOS'
  s.dependency 'SwiftyTesseract401'

  s.platform = :osx, '10.13'
  s.swift_version = '5.3'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_VERSION' => '5.3',
    'OTHER_SWIFT_FLAGS' => '-DUSE_SWIFTY_TESSERACT'
  }
  s.frameworks = 'Foundation', 'AppKit'
end