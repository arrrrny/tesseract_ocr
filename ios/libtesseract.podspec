Pod::Spec.new do |s|
  s.name             = 'libtesseract'
  s.version          = '0.2.0'
  s.summary          = 'Tesseract OCR xcframework for SwiftyTesseract'
  s.description      = 'Binary xcframework for Tesseract OCR, required by SwiftyTesseract 4.x'
  s.homepage         = 'https://github.com/SwiftyTesseract/libtesseract'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Steven Sherry' => 'steven.sherry@gmail.com' }
  s.source           = { :http => 'file:' + File.expand_path('libtesseract.xcframework', __dir__) }
  s.ios.deployment_target = '11.0'
  s.vendored_frameworks = 'libtesseract.xcframework'
end
