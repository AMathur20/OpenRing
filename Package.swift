// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenRing",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OpenRingCore",
            targets: ["OpenRingCore"]
        ),
        .library(
            name: "OpenRingStorage",
            targets: ["OpenRingStorage"]
        ),
        .library(
            name: "OpenRingMock",
            targets: ["OpenRingMock"]
        ),
        .library(
            name: "OpenRingAI",
            targets: ["OpenRingAI"]
        ),
        .library(
            name: "OpenRingUI",
            targets: ["OpenRingUI"]
        ),
        .executable(
            name: "OpenRingApp",
            targets: ["OpenRingApp"]
        ),
        .executable(
            name: "openring-mock",
            targets: ["MockRunner"]
        )
    ],
    dependencies: [],
    targets: [
        // Core protocol, cryptography, event decoders, packet reassembly & DSP
        .target(
            name: "OpenRingCore",
            dependencies: [],
            path: "Sources/OpenRingCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // Persistence layer: SQLite WAL mode via Apple libsqlite3 (zero external dependencies)
        .target(
            name: "OpenRingStorage",
            dependencies: [
                "OpenRingCore"
            ],
            path: "Sources/OpenRingStorage",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // Virtual BLE Peripheral & Synthetic Telemetry Generator
        .target(
            name: "OpenRingMock",
            dependencies: ["OpenRingCore"],
            path: "Sources/OpenRingMock",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // On-device Edge AI: quantized Llama-3.2-3B-Instruct inference engine & recovery synthesis
        .target(
            name: "OpenRingAI",
            dependencies: [
                "OpenRingCore",
                "OpenRingStorage"
            ],
            path: "Sources/OpenRingAI",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // Native SwiftUI presentation layer & interactive 60 FPS charts (DEC-018)
        .target(
            name: "OpenRingUI",
            dependencies: [
                "OpenRingCore",
                "OpenRingStorage",
                "OpenRingAI"
            ],
            path: "Sources/OpenRingUI",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // Application entry point wrapper
        .executableTarget(
            name: "OpenRingApp",
            dependencies: [
                "OpenRingUI",
                "OpenRingCore",
                "OpenRingStorage",
                "OpenRingAI"
            ],
            path: "Sources/OpenRingApp",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // macOS CLI tool to run the virtual Oura peripheral
        .executableTarget(
            name: "MockRunner",
            dependencies: ["OpenRingMock"],
            path: "Sources/MockRunner",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // Unit tests for core protocol, framing, crypto, decoders & DSP
        .testTarget(
            name: "OpenRingCoreTests",
            dependencies: ["OpenRingCore"],
            path: "Tests/OpenRingCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // Unit tests for local storage & queries
        .testTarget(
            name: "OpenRingStorageTests",
            dependencies: ["OpenRingStorage"],
            path: "Tests/OpenRingStorageTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // Unit tests for virtual mock peripheral
        .testTarget(
            name: "OpenRingMockTests",
            dependencies: ["OpenRingMock"],
            path: "Tests/OpenRingMockTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // Unit tests for Edge AI engine, prompt builder & inference pipeline
        .testTarget(
            name: "OpenRingAITests",
            dependencies: [
                "OpenRingAI",
                "OpenRingCore",
                "OpenRingStorage"
            ],
            path: "Tests/OpenRingAITests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // Unit tests for UI ViewModels, formatting & presentation
        .testTarget(
            name: "OpenRingUITests",
            dependencies: [
                "OpenRingUI",
                "OpenRingCore",
                "OpenRingStorage",
                "OpenRingAI"
            ],
            path: "Tests/OpenRingUITests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

