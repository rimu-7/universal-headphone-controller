// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HeadphoneController",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "HeadphoneController",
            targets: ["HeadphoneController"]
        )
    ],
    targets: [
        .executableTarget(
            name: "HeadphoneController",
            dependencies: ["Sparkle"],
            path: "Sources/HeadphoneController",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
        ),
        .testTarget(
            name: "HeadphoneControllerTests",
            dependencies: ["HeadphoneController"],
            path: "Tests/HeadphoneControllerTests"
        )
    ]
)
