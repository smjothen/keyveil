// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SVGPopup",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SVGPopup",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
