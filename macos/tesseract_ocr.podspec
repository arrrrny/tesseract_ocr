#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tesseract_ocr.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'tesseract_ocr'
  s.version          = '0.5.1'
  s.summary          = 'Tesseract OCR 4 Flutter'
  s.description      = <<-DESC
Tesseract 4 adds a new neural net (LSTM) based OCR engine which is focused on line recognition. It has unicode (UTF-8) support, and can recognize more than 100 languages.
                       DESC
  s.homepage         = 'https://github.com/arrrrny/tesseract_ocr'
  s.license          = { :file => '../LICENSE', :type => 'BSD' }
  s.author           = { 'Ahmet TOK' => 'arny@paratoner.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'tesseract_ocr/Sources/tesseract_ocr/**/*'
  s.resource_bundles = {
    'tesseract_ocr_privacy' => ['tesseract_ocr/Sources/tesseract_ocr/PrivacyInfo.xcprivacy']
  }

  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.3'
end
