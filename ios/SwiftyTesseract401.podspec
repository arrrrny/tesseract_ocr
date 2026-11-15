Pod::Spec.new do |s|
  s.name             = 'SwiftyTesseract401'
  s.version          = '4.0.1'
  s.module_name      = 'SwiftyTesseract'
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
  s.osx.deployment_target = '10.13'
  s.swift_version = '5.3'
  
  s.source_files = 'Sources/SwiftyTesseract/**/*.swift'
  # The sources split their UIKit/AppKit extras behind canImport, and the upstream
  # package manifest declares both Apple platforms, so the macOS build links
  # AppKit instead of UIKit.
  s.ios.frameworks = 'Foundation', 'UIKit'
  s.osx.frameworks = 'Foundation', 'AppKit'
  
  # libtesseract 0.0.x is an unrelated pod on trunk whose podspec excludes the
  # arm64 simulator slice, which would force EXCLUDED_ARCHS into every app that
  # integrates this pod. Only the 0.2.x xcframework line ships an arm64 simulator
  # slice, and the pin keeps a future 0.3/1.0 from silently changing that binary
  # contract.
  s.dependency 'libtesseract', '~> 0.2.0'
  
  s.libraries = 'z', 'c++'
  
  s.pod_target_xcconfig = { 
    'SWIFT_VERSION' => '5.3'
  }
end