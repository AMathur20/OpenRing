# OpenRing

> **An offline, zero-telemetry, local-first iOS client for Oura Ring hardware (primarily Gen 3).**

OpenRing restores device sovereignty by establishing an offline bridge directly between the Oura ring’s local flash memory and your Apple device. It circumvents mandatory cloud accounts and recurring subscription paywalls, running entirely on-device with zero network sockets, native digital signal processing (DSP), local SQLite persistence, and quantized edge LLM recovery coaching.

---

## Architectural Invariants & Core Pillars

| Dimension | Architectural Decision | Core Rationale |
| :--- | :--- | :--- |
| **Data Sovereignty** | 100% Offline & Air-Gapped | The application sandbox contains **zero network entitlements**. No remote servers, analytics SDKs, or cloud accounts. |
| **Primary Platform** | Native iOS (Swift 6 & SwiftUI) | Low-level access to CoreBluetooth background state restoration, unified memory management, and Metal/Accelerate vector math. |
| **Concurrency Model** | Swift 6 Isolated Actors | Strict compiler-enforced data-race freedom (`-strict-concurrency=complete`) across BLE packet ingestion, persistence, and AI inference. |
| **Local Persistence** | SQLite in WAL Mode (Native `libsqlite3`) | Thread-safe concurrent reads/writes; renders 60 FPS time-series charts without blocking BLE background packet ingestion. |
| **Biometric Decoding** | Lossless Raw + Firmware Staging | Persists raw immutable byte payloads. Extracts on-device sleep stages (2-bit hypnogram) directly from ring firmware history events. |
| **Edge AI Engine** | `llama.cpp` Metal + Llama-3.2-3B INT4 | Generates structured 3-paragraph recovery summaries (<140 words) strictly in the foreground within safe memory bounds (~1.85 GB peak RAM). |
| **Regulatory Stance** | Functional Wellness / Recovery Framing | Strictly sports physiology and sleep hygiene. Rejects diagnostic claims to maintain FDA SaMD exemption and App Store 1.4.1 compliance. |

---

## Current Status & Phased Roadmap

We are executing development in structured, test-verified phases:

```
[Phase 1: Specs & Protocol Discovery] ─────────► [COMPLETED]
[Phase 2: Scaffolding & Virtual Mock Harness] ──► [COMPLETED]
[Phase 3: CoreBluetooth Central Engine] ───────► [COMPLETED (25/25 Tests Passing)]
[Phase 4: Local Storage Engine Integration] ────► [NEXT UP]
[Phase 5: Deterministic DSP & Readiness] ──────► [UPCOMING]
[Phase 6: Edge AI Engine (llama.cpp Metal)] ───► [UPCOMING]
[Phase 7: SwiftUI Native Views & 60 FPS Charts] ─► [UPCOMING]
[Phase 8: Background Sync & App Store Audit] ──► [UPCOMING]
```

### ✅ Phase 1: Protocol Discovery & Clarifications (Completed)
* Reverse-engineered proprietary Oura BLE protocol from decompiled ring firmware (`libringeventparser.so` via `Th0rgal/open_oura`).
* Verified real Nordic GATT UUIDs: Service `98ed0001`, Write `98ed0002`, Notify `98ed0003`.
* Confirmed App-Level Auth Handshake: **AES-128 / ECB mode with PKCS#7 padding** over a 15-byte random challenge nonce and a 16-byte shared key.
* Verified that Oura Gen 3 hardware computes sleep stages on-device (tags `0x4B`, `0x4E`, `0x5A`) as 2-bit hypnogram codes (`DEEP`, `LIGHT`, `REM`, `AWAKE`).
* Logged and accepted all 15 core Architecture Decision Records ([`Decisions Log.md`](Decisions%20Log.md)).

### ✅ Phase 2: Scaffolding, Core Engine & Mock Harness (Completed)
* Built **`OpenRingCore`** (Swift 6 strict concurrency library):
  * Low-level `Packet` framing with wire encoding and multi-packet notification deframing (`parseMany`).
  * Request builders for firmware inquiry, battery, auth nonce, auth response, key provisioning, and time synchronization.
  * `OuraAuthCrypto` implementing AES-128-ECB PKCS#7 challenge-response encryption and secure key generation.
  * History event decoders (`RingEvent`) for HRV (`0x5D`), skin temperature (`0x46`/`0x69`/`0x75`), on-device sleep stages (`0x4B`), and IBI streams.
  * `PacketReassemblyEngine` isolated actor handling sliding-window byte buffering and fragmentation.
  * `SignalProcessor` Accelerate (`vDSP`) rMSSD calculation, 14-day exponential moving average baselines, and multi-factor readiness scoring.
* Built **`OpenRingStorage`**:
  * GRDB.swift SQLite persistence models (`RawIngestionRecord`, `BiometricSampleRecord`, `TemperatureTelemetryRecord`, `SleepEpisodeRecord`, `DailyEvaluationRecord`).
  * `DatabaseService` isolated actor managing WAL mode and automated schema migrations.
* Built **`OpenRingMock`**:
  * CoreBluetooth `CBPeripheralManager` simulator advertising as an Oura Ring Gen 3 on `98ed0001`.
  * `MockDataGenerator` synthesizing full 7-hour night sessions (84 5-minute intervals = 252 events) and challenge nonces.
  * `openring-mock` CLI runner for macOS.
* Built and verified full automated test suite: **18 tests passed, 0 failures**.

### ✅ Phase 3: CoreBluetooth Central Engine (Completed)
* Implemented `BLEEngine` isolated actor:
  * `CBCentralManager` state machine and background restoration (`willRestoreState`).
  * Passive advertisement scanning targeting Service `98ed0001`.
  * Automated AES-128-ECB challenge handshake execution upon connection and notification activation.
  * Non-isolated `states`, `events`, and `discoveredRings` asynchronous streams (`AsyncStream`).
  * Telemetry ingestion feeding directly into `PacketReassemblyEngine`.
  * Verified with automated state machine, handshake simulation, and event stream tests: **25 tests passed, 0 failures**.

### ⏳ Phase 4: Local Storage Engine & SyncCoordinator Pipeline (Next Up)
* Implement `DatabaseService` actor using native `SQLite3` in WAL mode (zero external package dependencies).
* Schema migrations for `raw_ingestion_log`, `biometric_samples`, `temperature_telemetry`, `sleep_episodes`, `daily_evaluations`.
* Implement `SyncCoordinator` actor in `OpenRingCore` bridging `BLEEngine.events` into typed database tables.
* Benchmark range query latency (<10ms target for 30 days / 8,640 samples).

---

## Repository Structure

```
openring/
├── README.md                             # Project overview & status
├── Decisions Log.md                      # Architecture Decision Records (DEC-001 - DEC-013)
├── Implementation Plan.md                # 8-Phase implementation roadmap & specs
├── OpenRing App Engineering Docs.md      # Unified PRD & Technical Design Document
├── Package.swift                         # Swift 6 package manifest
├── Sources/
│   ├── OpenRingCore/                     # Core protocol, crypto, decoders, reassembly & DSP
│   │   ├── Crypto/
│   │   │   └── OuraAuthCrypto.swift      # AES-128-ECB PKCS#7 challenge encryption
│   │   ├── Decoders/
│   │   │   ├── EventPayloads.swift       # Typed models (HRV, temp, sleep hypnograms, IBI)
│   │   │   └── RingEvent.swift           # Decisecond timestamp parser & tag router
│   │   ├── DSP/
│   │   │   └── SignalProcessor.swift     # Accelerate vDSP rMSSD, EMA, readiness formula
│   │   ├── Engine/
│   │   │   └── PacketReassemblyEngine.swift # Swift 6 isolated actor for BLE stream
│   │   └── Protocol/
│   │       ├── GATTConstants.swift       # Nordic 0x98ED UUIDs & protocol constants
│   │       └── Packet.swift              # Tag/Length/Payload framing & request builders
│   ├── OpenRingStorage/                  # SQLite WAL persistence via GRDB.swift
│   │   ├── DatabaseService.swift         # Thread-safe database actor & migrations
│   │   └── Models.swift                  # Persisted SQL records
│   ├── OpenRingMock/                     # Virtual peripheral & synthetic telemetry generator
│   │   ├── MockDataGenerator.swift       # Full night session stream generator
│   │   └── OuraRingMock.swift            # CBPeripheralManager GATT simulator
│   └── MockRunner/
│       └── main.swift                    # CLI executable to run the mock ring on macOS
└── Tests/
    ├── OpenRingCoreTests/                # Unit test suites for protocol, crypto, decoders, DSP
    ├── OpenRingMockTests/                # Tests for synthetic data & mock peripheral
    ├── OpenRingStorageTests/             # Tests for GRDB SQLite tables & range queries
    └── TestRunner/
        └── main.swift                    # Consolidated test executor
```

---

## Quick Start & Verification

### Prerequisites
* macOS 14.0+
* Swift 6.0+ (Command Line Tools or Xcode 16+)

### Run Automated Tests
To build and execute the full test suite verifying framing, AES-128 cryptography, event decoders, DSP algorithms, and mock generation:

```bash
# 1. Compile OpenRingCore dynamic library
swiftc -module-cache-path .build/cache -parse-as-library \
  Sources/OpenRingCore/Protocol/*.swift \
  Sources/OpenRingCore/Crypto/*.swift \
  Sources/OpenRingCore/Decoders/*.swift \
  Sources/OpenRingCore/DSP/*.swift \
  Sources/OpenRingCore/Engine/*.swift \
  -emit-library -module-name OpenRingCore -o .build/libOpenRingCore.dylib

# 2. Compile OpenRingMock library
swiftc -module-cache-path .build/cache -I .build -L .build -lOpenRingCore \
  -parse-as-library Sources/OpenRingMock/*.swift \
  -emit-library -module-name OpenRingMock -o .build/libOpenRingMock.dylib

# 3. Execute test suite
DYLD_LIBRARY_PATH=.build swift -module-cache-path .build/cache \
  -I .build -L .build -lOpenRingCore -lOpenRingMock \
  Tests/TestRunner/main.swift
```

Expected output:
```
==================================================
      OpenRing Swift 6 Core & Mock Test Suite     
==================================================

--- [1] Protocol & Packet Framing ---
  ✅ [PASS] Packet round-trip encode and decode
  ✅ [PASS] Parse multiple concatenated packets in one notification buffer
  ✅ [PASS] PacketReassemblyEngine handles fragmented chunks across BLE packets
  ✅ [PASS] Request builders emit valid protocol byte shapes

--- [2] Cryptographic Handshake (AES-128-ECB PKCS#7) ---
  ✅ [PASS] Random 16-byte key generation
  ✅ [PASS] AES-128-ECB PKCS#7 encryption and decryption round-trip
  ✅ [PASS] Validation of invalid key and nonce lengths
  ✅ [PASS] AuthResult status decoding

--- [3] History Event Decoders ---
  ✅ [PASS] Decode HRV Event (Tag 0x5D)
  ✅ [PASS] Decode Temperature Event (Tag 0x46)
  ✅ [PASS] Decode Sleep Phase Hypnogram (Tag 0x4B)

--- [4] Deterministic DSP & Readiness Algorithm ---
  ✅ [PASS] rMSSD computation on synthetic IBI series
  ✅ [PASS] Artifact filtering in rMSSD computation
  ✅ [PASS] Exponential Moving Average 14-day update
  ✅ [PASS] Readiness score bounds and penalty calculation

--- [5] Virtual BLE Mock & Synthetic Stream Generator ---
  ✅ [PASS] Synthetic challenge nonce is 15 bytes
  ✅ [PASS] Synthetic full night stream parses through reassembly engine
  ✅ [PASS] Challenge-response simulation round-trip

--- [6] BLEEngine Central State Machine & Streams ---
  ✅ [PASS] BLEEngine initializes with valid 16-byte key
  ✅ [PASS] BLEEngine streams and state transition verification
  ✅ [PASS] BLEEngine history request & time sync builders
  ✅ [PASS] BLEEngine handles incoming challenge nonce notification
  ✅ [PASS] BLEEngine handles authentication success packet
  ✅ [PASS] BLEEngine handles authentication failure packet
  ✅ [PASS] BLEEngine routes incoming history packets to events stream

==================================================
 Test Results: 25 Passed, 0 Failed
==================================================
```

### Run the Virtual BLE Ring Peripheral
You can advertise your Mac as an Oura Ring Gen 3 to test discovery, connection, and auth without physical hardware:

```bash
# Build CLI executable
swiftc -module-cache-path .build/cache -I .build -L .build \
  -lOpenRingCore -lOpenRingMock Sources/MockRunner/main.swift \
  -o .build/openring-mock

# Launch virtual peripheral
DYLD_LIBRARY_PATH=.build .build/openring-mock
```

---

## Documentation Index

* [**`OpenRing App Engineering Docs.md`**](OpenRing%20App%20Engineering%20Docs.md): Full Product Requirements Document (PRD) and Technical Design Document (TDD).
* [**`Implementation Plan.md`**](Implementation%20Plan.md): Detailed 8-phase technical execution plan, protocol specifications, and verification strategy.
* [**`Decisions Log.md`**](Decisions%20Log.md): Architecture Decision Records (ADRs) tracking all 15 accepted decisions.
* [**`LICENSE`**](LICENSE): GNU General Public License v3.0 with Apple App Store & Google Play Store Exception.

---

## License

OpenRing is licensed under the **GNU General Public License Version 3 (GPLv3)** with an explicit **Section 7 Additional Permission (Apple App Store & Google Play Store Exception)**.

* **Anti-Paywall Protection:** Any modified or derivative works **must remain 100% free and open-source under GPLv3**. Third parties are legally barred from taking this source code and publishing a closed-source, paywalled app.
* **Reciprocal Upstream Contributions:** Any modifications made by contributors must be published openly under the same terms.
* **App Store & Google Play Compatibility:** Includes an explicit exception granting legal permission to distribute through the Apple App Store, TestFlight, and Google Play Store without violating GPLv3 terms.

See the full [**`LICENSE`**](LICENSE) for details.

