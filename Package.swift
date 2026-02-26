// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Friday",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Friday",
            path: "Sources/Friday"
        ),
    ]
)
