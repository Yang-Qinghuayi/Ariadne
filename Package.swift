// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ariadne",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AriadneCore",
            targets: ["AriadneCore"]
        ),
        .executable(
            name: "Ariadne",
            targets: ["Ariadne"]
        )
    ],
    targets: [
        .target(
            name: "AriadneCore",
            dependencies: [],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "Ariadne",
            dependencies: ["AriadneCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "AriadneCoreTests",
            dependencies: ["AriadneCore"]
        )
    ]
)
