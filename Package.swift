// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DialnRay",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DialnRayCore", targets: ["DialnRayCore"]),
        .executable(name: "DialnRay", targets: ["DialnRay"]),
    ],
    targets: [
        .target(
            name: "DialnRayCore",
            path: "Sources/DialnRayCore"
        ),
        .executableTarget(
            name: "DialnRay",
            dependencies: ["DialnRayCore"],
            path: "Sources/DialnRay",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Vision"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "DialnRayCoreTests",
            dependencies: ["DialnRayCore"],
            path: "Tests/DialnRayCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
