// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Keyveil",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Keyveil",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
