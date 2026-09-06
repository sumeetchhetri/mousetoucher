// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MouseToucher",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "MouseToucherLib",
            targets: ["MouseToucherLib"]
        )
    ],
    targets: [
        .target(
            name: "MouseToucherLib",
            dependencies: [],
            path: ".",
            exclude: [
                "Tests", "build", "AppDelegate.swift", "MultitouchManager.swift",
                "Preferences.swift", "main.swift", "MultitouchBridge.h", "Info.plist",
                "README.md", "TESTING.md", "LICENSE", "mousetoucher-dark.png",
                "mousetoucher-light.png", "build.sh", "run_tests.sh"
            ],
            sources: ["TapDetector.swift", "TwoFingerTapDetector.swift"]
        ),
        .testTarget(
            name: "MouseToucherTests",
            dependencies: ["MouseToucherLib"],
            path: "Tests"
        )
    ]
)
