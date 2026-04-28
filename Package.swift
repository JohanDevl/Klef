// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Klef",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "klef",
            path: "Sources/klef",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
