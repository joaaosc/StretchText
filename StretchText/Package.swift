// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "StretchText",
    platforms: [
        .iOS(.v27),
        .macOS(.v27),
    ],
    products: [
        .library(name: "StretchText", targets: ["StretchText"]),
    ],
    targets: [
        .target(name: "StretchText"),
        .testTarget(name: "StretchTextTests", dependencies: ["StretchText"]),
    ],
    swiftLanguageModes: [.v6]
)
