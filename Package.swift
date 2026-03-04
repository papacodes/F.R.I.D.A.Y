// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Friday",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", branch: "main"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.16.0"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.19.0")
    ],
    targets: [
        .executableTarget(
            name: "Friday",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")
            ],
            path: "Sources/Friday",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Metal"),
                .linkedFramework("Accelerate")
            ]
        ),
    ]
)
