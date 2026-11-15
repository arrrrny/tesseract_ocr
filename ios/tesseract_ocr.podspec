#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'tesseract_ocr'
  s.version          = '0.6.0'
  s.summary          = 'Tesseract OCR 4 Flutter'
  s.description      = <<-DESC
Tesseract 4 adds a new neural net (LSTM) based OCR engine which is focused on line recognition. It has unicode (UTF-8) support, and can recognize more than 100 languages.
                       DESC
  s.homepage         = 'https://paratoner.io'
  s.license          = { :file => '../LICENSE',:type => 'BSD' }
  s.author           = { 'Ahmet TOK' => 'arny@paratoner.io' }
  s.source           = { :path => '.' }
  # Compile the shared SwiftPM sources (the single source of truth, also built by
  # Package.swift). CocoaPods resolves these patterns against the podspec's own
  # directory (ios/), so the shared tree is reached as ../Sources. The old
  # Classes/SwiftTesseractOcrPlugin.swift was a byte-identical copy that drifted
  # and shipped compile errors twice; it is gone.
  s.source_files = '../Sources/tesseract_ocr/*.swift', 'Classes/*.{h,m,mm}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'SwiftyTesseract401' # Use 4.0.1 from GitHub via custom podspec
  s.ios.deployment_target = '14.0'
  s.swift_version = '5.3'
  s.pod_target_xcconfig = {
    'SWIFT_VERSION' => '5.3'
  }
  s.frameworks = 'Foundation', 'UIKit', 'Vision'
end
