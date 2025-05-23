Pod::Spec.new do |s|
  s.name             = 'SwiftyTesseract401'
  s.version          = '4.0.1'
  s.summary          = 'A Swift wrapper around Tesseract for OCR'
  s.description      = <<-DESC
SwiftyTesseract is a Swift wrapper around Tesseract OCR. It provides a simple interface to perform OCR on images.
This podspec allows using SwiftyTesseract 4.0.1 from GitHub with CocoaPods.
                       DESC
  s.homepage         = 'https://github.com/SwiftyTesseract/SwiftyTesseract'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Steven Sherry' => 'steven.sherry@gmail.com' }
  s.source           = { :git => 'https://github.com/SwiftyTesseract/SwiftyTesseract.git', :tag => '4.0.1' }
  
  s.ios.deployment_target = '11.0'
  s.swift_version = '5.3'
  
  s.source_files = 'Sources/SwiftyTesseract/**/*.swift'
  s.frameworks = 'Foundation', 'UIKit'
  
  s.dependency 'libtesseract'
  
  s.libraries = 'z', 'c++'
  
  s.pod_target_xcconfig = { 
    'SWIFT_VERSION' => '5.3'
  }
end