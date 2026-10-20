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
        .library(name: "StretchTextGeneration", targets: ["StretchTextGeneration"]),
        .library(name: "StretchTextUI", targets: ["StretchTextUI"]),
    ],
    targets: [
        .target(name: "StretchText"),
        .target(name: "StretchTextGeneration", dependencies: ["StretchText"]),
        .target(name: "StretchTextUI", dependencies: ["StretchText"]),
        .executableTarget(
            name: "StretchTextEvaluation",
            dependencies: ["StretchText", "StretchTextGeneration"],
            path: "Evaluation/Sources"
        ),
        .testTarget(name: "StretchTextTests", dependencies: ["StretchText"]),
        .testTarget(name: "StretchTextGenerationTests", dependencies: ["StretchTextGeneration"]),
        .testTarget(name: "StretchTextUITests", dependencies: ["StretchTextUI"]),
    ],
    swiftLanguageModes: [.v6]
)
