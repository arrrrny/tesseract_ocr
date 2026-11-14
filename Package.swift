// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Apple platforms only (iOS, macOS).
//
// Flutter builds Linux plugins with CMake (see the top-level linux/ directory),
// not Swift Package Manager, so this manifest intentionally targets Apple. An
// earlier `#if os(Linux)` branch compiled a Swift Linux plugin, but that path is
// unused by Flutter and redeclared SwiftTesseractOcrPlugin, which broke
// `swift build` on Linux; Linux support lives entirely in linux/.
let package = Package(
    name: "tesseract_ocr",
    platforms: [.iOS(.v11), .macOS(.v10_13)],
    products: [
        .library(
            name: "tesseract-ocr",
            targets: ["tesseract_ocr"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyTesseract/SwiftyTesseract.git", from: "4.0.1")
    ],
    targets: [
        .target(
            name: "tesseract_ocr",
            dependencies: [
                .product(name: "SwiftyTesseract", package: "SwiftyTesseract")
            ],
            path: "Sources/tesseract_ocr"
        )
    ]
)