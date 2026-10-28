// swift-tools-version:5.9
import PackageDescription

// TapTheTabCore is plain Swift + Foundation so it builds and tests on any platform.
// The TapTheTab app target uses AppKit and only exists on macOS.

var products: [Product] = [
    .library(name: "TapTheTabCore", targets: ["TapTheTabCore"]),
]

var targets: [Target] = [
    .target(
        name: "TapTheTabCore",
        path: "Sources/TapTheTabCore"
    ),
    .testTarget(
        name: "TapTheTabCoreTests",
        dependencies: ["TapTheTabCore"],
        path: "Tests/TapTheTabCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "TapTheTab", targets: ["TapTheTab"]))
targets.append(
    .executableTarget(
        name: "TapTheTab",
        dependencies: ["TapTheTabCore"],
        path: "Sources/TapTheTab",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("ApplicationServices"),
            .linkedFramework("ScreenCaptureKit"),
            .linkedFramework("ServiceManagement"),
            .linkedFramework("SwiftUI"),
        ]
    )
)
#endif

let package = Package(
    name: "TapTheTab",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets,
    swiftLanguageVersions: [.v5]
)
