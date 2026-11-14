Pod::Spec.new do |s|
  s.name             = 'libtesseract'
  s.version          = '0.2.0'
  s.summary          = 'Tesseract OCR xcframework for SwiftyTesseract'
  s.description      = 'Binary xcframework for Tesseract OCR, required by SwiftyTesseract 4.x'
  s.homepage         = 'https://github.com/SwiftyTesseract/libtesseract'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Steven Sherry' => 'steven.sherry@gmail.com' }

  # The binary is not distributed through CocoaPods or pub.dev, so the consumer
  # places it here, next to this podspec, in the PLUGIN's ios/ directory (the
  # directory the pod is consumed by :path from — NOT the app's own ios/).
  # See CUSTOM_PODS_README.md.
  xcframework = File.expand_path('libtesseract.xcframework', __dir__)
  unless File.exist?(xcframework)
    raise <<-MSG
libtesseract.xcframework is missing from #{__dir__}.

This pod is a local :path pod: CocoaPods consumes it from the tesseract_ocr
plugin's ios/ directory, so the xcframework must live beside this podspec
(ios/libtesseract.xcframework), not in your app's ios/ directory.

CocoaPods silently drops a vendored framework it cannot find, which surfaces
much later as a link error or "Couldn't find module" — this failure exists so
you find it here instead.

Download libtesseract-0.2.0.xcframework.zip from
https://github.com/SwiftyTesseract/libtesseract/releases/tag/0.2.0,
unzip it, and place the resulting libtesseract.xcframework folder here.
MSG
  end

  s.source           = { :http => 'file:' + xcframework }
  s.ios.deployment_target = '11.0'
  s.vendored_frameworks = 'libtesseract.xcframework'
end
