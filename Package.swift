// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if os(Linux)
// Linux configuration: uses system tesseract via C++ interop
let package = Package(
    name: "tesseract_ocr",
    platforms: [.iOS(.v11), .macOS(.v10_13)],
    products: [
        .library(
            name: "tesseract-ocr",
            targets: ["tesseract_ocr"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "tesseract_ocr",
            dependencies: ["TesseractOcrCpp"],
            path: "Sources/tesseract_ocr"
        ),
        .systemLibrary(
            name: "TesseractOcrCpp",
            path: "Sources/TesseractOcrCpp",
            pkgConfig: "tesseract",
            providers: [
                .apt(["libtesseract-dev", "libleptonica-dev"]),
                .yum(["tesseract-devel", "leptonica-devel"]),
            ]
        )
    ]
)
#else
// Apple platforms: uses SwiftyTesseract via SPM
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
#endif