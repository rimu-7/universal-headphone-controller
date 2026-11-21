// swift-tools-version: 6.4
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
            path: "Sources/HeadphoneController",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
