#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'tesseract_ocr'
  s.version          = '0.4.0'
  s.summary          = 'Tesseract OCR 4 Flutter'
  s.description      = <<-DESC
Tesseract 4 adds a new neural net (LSTM) based OCR engine which is focused on line recognition. It has unicode (UTF-8) support, and can recognize more than 100 languages.
                       DESC
  s.homepage         = 'https://paratoner.io'
  s.license          = { :file => '../LICENSE',:type => 'BSD' }
  s.author           = { 'Ahmet TOK' => 'arny@paratoner.io' }
  s.source           = { :path => '.' }
  # Include only the plugin's source files, exclude the old local SwiftyTesseract files
  s.source_files = 'Classes/*.{h,m,mm,swift}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'SwiftyTesseract401' # Use 4.0.1 from GitHub via custom podspec
  s.ios.deployment_target = '14.0'
  s.swift_version = '5.3'
  s.pod_target_xcconfig = { 
    'SWIFT_VERSION' => '5.3',
    'OTHER_SWIFT_FLAGS' => '-DUSE_SWIFTY_TESSERACT'
  }
  s.frameworks = 'Foundation', 'UIKit', 'Vision'
end
