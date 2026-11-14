// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// NOTE: this conditional is evaluated on the machine running `swift build`
// (the host), not on the target platform. That is fine for Flutter plugins —
// each platform builds natively, so a macOS build always takes the #else
// (Apple) branch and a Linux build always takes the Linux branch. It does mean
// the manifest cannot cross-compile: an Apple-host build cannot produce a Linux
// binary, and vice versa.
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
