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
        .executable(
            name: "openring-mock",
            targets: ["MockRunner"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
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

        // Persistence layer: SQLite via GRDB.swift (WAL mode)
        .target(
            name: "OpenRingStorage",
            dependencies: [
                "OpenRingCore",
                .product(name: "GRDB", package: "GRDB.swift")
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
        )
    ]
)

