# OpenRing v0.1 Release Notes

**Release Version:** `v0.1`  
**Target Platforms:** iOS 17.0+ (iPhone & iPad), macOS 14.0+  
**License:** GNU General Public License v3.0 (with Apple App Store & Google Play Exception)  
**Supported Hardware:** Oura Ring Gen 3 (Horizon & Heritage, Nordic Semiconductor nRF52 BLE)  

---

## Executive Summary

**OpenRing v0.1** is the inaugural release of the fully offline, zero-telemetry, open-source client for Oura Ring hardware. It delivers an end-to-end local health intelligence stack that replaces proprietary cloud subscriptions with sovereign on-device processing.

From Bluetooth Low Energy (BLE) packet reassembly and AES-128 cryptographic handshakes, to high-performance SQLite WAL persistence, Apple Accelerate (`vDSP`) digital signal processing, 60 FPS interactive hypnogram charts, and an on-device Edge AI recovery coach powered by a 4-bit quantized Llama-3.2-3B model running on Apple Metal GPU—**every byte of telemetry remains strictly on your device.**

---

## What's Included in v0.1

### 1. Core Protocol & Cryptography (`OpenRingCore`)
* **Nordic GATT Protocol Parser:** Fully decodes Oura's proprietary framing (`[Tag: 1B, Length: 1B, Payload: LB]`) and decisecond timestamp history events.
* **AES-128-ECB PKCS#7 Handshake:** Automated cryptographic challenge-response authentication protocol with on-charger key provisioning (Packet `0x24`) and secure key management.
* **Lossless Multi-Packet Frame Reassembly:** Swift 6 isolated actor (`PacketReassemblyEngine`) handling fragmented BLE MTU notifications with zero dropped packets.
* **History Event Decoders:** Typed decoders for HRV 5-minute averages (Tag `0x5D`), centi-°C nocturnal temperature series (Tag `0x46`), and on-device sleep stage classifications (Tag `0x4B`).

### 2. Native SQLite WAL Local Storage (`OpenRingStorage`)
* **Zero-Cloud Architecture:** Native C-API SQLite engine configured with Write-Ahead Logging (WAL) and synchronous normal pragmas.
* **Lossless Archival:** Full audit trail archiving raw byte streams in `raw_ingestion_log` before parsed biometrics are committed.
* **Sub-Millisecond Range Queries:** Indexed prepared statements delivering 30-day continuous biometric range queries (8,640 samples) in **0.76 ms** (target: $< 10\text{ ms}$).
* **Automated Sync Pipeline (`SyncCoordinator`):** Actor-isolated background ingestion subscribing to live BLE streams with automatic post-sleep evaluation triggers.

### 3. Deterministic Physiological Algorithms
* **HRV (rMSSD) Calculation:** Computes true root mean square of successive differences from inter-beat intervals (IBI) with physiological motion and ectopic beat filtering.
* **14-Day Rolling Baselines:** Exponential Moving Average (EMA, $\alpha = 2/15 \approx 0.1333$) tracking individual physiological baselines for resting heart rate, HRV, and temperature.
* **Deterministic Readiness Score ($0–100$, DEC-003):** Multi-factor autonomic recovery formulation incorporating RHR delta penalties, HRV delta penalties, thermal deviation offsets, and sleep efficiency.
* **Deterministic Sleep Score ($0–100$, DEC-016):** Polysomnography-weighted formulation scoring total sleep duration, sleep efficiency, restorative deep sleep, and REM sleep.
* **Open Heuristic Sleep Stage Fallback (DEC-011):** Classifies sleep stages (Deep, Light, REM, Awake) based on autonomic heart rate dips and accelerometer motion intensity during hardware hypnogram gaps.

### 4. On-Device Edge AI Engine (`OpenRingAI`)
* **Bundled `Llama-3.2-3B-Instruct` (INT4, ~1.9 GB):** Runs locally on device via Apple Metal GPU acceleration for sub-second, zero-network token generation.
* **Foreground Jetsam Defense Gate (DEC-007, DEC-017):** Strict application lifecycle gate blocking model execution in the background to guarantee compliance with iOS 30–60 MB background memory ceilings.
* **Non-Diagnostic Sports Science Synthesis (DEC-005, DEC-012):** Deterministic instruct prompt producing a structured 3-paragraph recovery summary (*Autonomic Load*, *Sleep Architecture*, *Actionable Recovery Protocol*) under 140 words with prominent FDA SaMD disclaimers.
* **Automated SQLite Persistence:** Live token streaming via `AsyncStream<String>` automatically commits completed markdown advice to `daily_evaluations`.

### 5. Native SwiftUI Presentation Layer (`OpenRingUI` & `OpenRingApp`)
* **Modular Library Architecture (DEC-018):** UI separated into standalone `OpenRingUI` framework with thin `OpenRingApp` executable wrapper.
* **4-Tab Navigation Shell:**
  - **Tab 1 (Readiness Dashboard):** Circular score gauge ($0–100$) animated with recovery color tiers, 14-day rolling baseline comparison cards, and live BLE header.
  - **Tab 2 (Sleep Architecture):** 60 FPS interactive hypnogram chart (SwiftUI `Charts`) with stage scrubbing, stage duration metrics, and deterministic Sleep Score.
  - **Tab 3 (Edge AI Recovery Coach):** Live typewriter card rendering local streaming recovery syntheses.
  - **Tab 4 (Settings & Data Sovereignty):** BLE connection management, AES-128 key generation and import, zero-network audit badge, SQLite database statistics, and 1-tap raw CSV / JSON export.
* **Adaptive Dynamic Theming:** Semantic system colors adapting between Apple Light Mode and Dark Mode.

### 6. iPhone Native Deployment
* **`OpenRing.xcodeproj`**: Complete native Xcode project configured for iOS 17.0+ with automatic code signing.
* **`Info.plist`**: Configured with Bluetooth usage descriptions and `bluetooth-central` background mode.
* **Testing Protocol**: Detailed physical ring testing guide in [`TESTING_WITH_RING.md`](TESTING_WITH_RING.md).

---

## Automated Test Suite Verification

OpenRing v0.1 passes all **56 automated unit, mathematical, and performance benchmark tests** with zero failures:

```
==================================================
      OpenRing Swift 6 Core & Mock Test Suite     
==================================================
  [1] Protocol & Packet Framing:           4 Passed
  [2] Cryptographic Handshake (AES-128):   4 Passed
  [3] History Event Decoders:              3 Passed
  [4] Deterministic DSP & Readiness:       7 Passed
  [5] Virtual BLE Mock & Streams:          3 Passed
  [6] BLEEngine Central State Machine:     7 Passed
  [7] Local Storage Engine (SQLite WAL):   9 Passed (30-day query: 0.76 ms)
  [8] SyncCoordinator Event Ingestion:    3 Passed
  [9] DailyEvaluationEngine Pipeline:      4 Passed
  [10] Edge AI Engine (LLMInference):      7 Passed
  [11] Native SwiftUI ViewModels & UI:     5 Passed
==================================================
 Test Results: 56 Passed, 0 Failed
==================================================
```

---

## Getting Started

1. Follow the **[Testing Protocol with a Physical Ring](TESTING_WITH_RING.md)** to build and run on your iPhone.
2. For testing without hardware, run the virtual ring peripheral on macOS:
   ```bash
   swiftc -module-cache-path .build/cache -I .build -L .build \
     -lOpenRingCore -lOpenRingMock Sources/MockRunner/main.swift \
     -o .build/openring-mock
   DYLD_LIBRARY_PATH=.build .build/openring-mock
   ```
