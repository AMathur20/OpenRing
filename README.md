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
[Phase 3: CoreBluetooth Central Engine] ───────► [COMPLETED]
[Phase 4: Local Storage Engine Integration] ────► [COMPLETED]
[Phase 5: Deterministic DSP & Readiness] ──────► [COMPLETED (44/44 Tests Passing)]
[Phase 6: Edge AI Engine (llama.cpp Metal)] ───► [COMPLETED (51/51 Tests Passing)]
[Phase 7: SwiftUI Native Views & 60 FPS Charts] ─► [NEXT UP]
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
  * Native SQLite persistence models (`RawIngestionRecord`, `BiometricSampleRecord`, `TemperatureTelemetryRecord`, `SleepEpisodeRecord`, `DailyEvaluationRecord`).
  * `DatabaseService` isolated actor managing WAL mode and automated schema migrations.
* Built **`OpenRingMock`**:
  * CoreBluetooth `CBPeripheralManager` simulator advertising as an Oura Ring Gen 3 on `98ed0001`.
  * `MockDataGenerator` synthesizing full 7-hour night sessions (84 5-minute intervals = 252 events) and challenge nonces.
  * `openring-mock` CLI runner for macOS.

### ✅ Phase 3: CoreBluetooth Central Engine (Completed)
* Implemented `BLEEngine` isolated actor:
  * `CBCentralManager` state machine and background restoration (`willRestoreState`).
  * Passive advertisement scanning targeting Service `98ed0001`.
  * Automated AES-128-ECB challenge handshake execution upon connection and notification activation.
  * Non-isolated `states`, `events`, and `discoveredRings` asynchronous streams (`AsyncStream`).
  * Telemetry ingestion feeding directly into `PacketReassemblyEngine`.

### ✅ Phase 4: Local Storage Engine & SyncCoordinator Pipeline (Completed)
* Implemented `DatabaseService` actor using native `SQLite3` in WAL mode (zero third-party dependencies):
  * Automated migrations creating indexed tables for `raw_ingestion_log`, `biometric_samples`, `temperature_telemetry`, `sleep_episodes`, and `daily_evaluations`.
  * Prepared statements delivering **0.82 ms query latency for 30 days of data** ($8,640$ 5-minute samples; target $<10\text{ ms}$).
  * `INSERT OR REPLACE` semantics guaranteeing idempotency across overlapping syncs.
* Implemented `SyncCoordinator` actor in `OpenRingStorage`:
  * Bridges `BLEEngine.events: AsyncStream<RingEvent>` into `DatabaseService`.
  * Lossless audit: writes raw incoming frames to `raw_ingestion_log`.
  * Transforms `.hrv`, `.temperature`, and `.sleepPhases` payloads into typed records.
  * High-throughput transactional batch persistence.
* Verified with automated test suite: **37 tests passed, 0 failures**.

### ✅ Phase 5: Deterministic DSP & Biometric Pipelines (COMPLETED)
* **Accelerate `vDSP` rMSSD Calculation:** Physiological artifact filtering ($|x_{i+1} - x_i| \le 300\text{ ms}$, $x_i \in [350, 1800]\text{ ms}$) with SIMD vector acceleration.
* **14-Day Rolling EMA Baselines:** $\alpha = 2/(14+1) \approx 0.1333$ continuous baseline convergence for Resting Heart Rate (RHR) and HRV.
* **Polysomnography-Aligned Sleep Score ($0 - 100$):** Deterministic 4-component formulation (DEC-016: duration 35, efficiency 30, deep sleep 20, REM sleep 15).
* **Multi-Factor Readiness Score ($0 - 100$):** Autonomic strain model penalizing elevated RHR, suppressed HRV, nocturnal temperature elevation ($> +0.50^\circ\text{C}$), and sleep efficiency deficits.
* **Heuristic Sleep Stage Fallback Classifier (DEC-011):** Classifies Awake, Deep, REM, and Light stages from 5-minute heart rate and motion intensity when hardware hypnograms are incomplete.
* **DailyEvaluationEngine Actor:** Correlates nocturnal biometrics and temperature records with sleep episodes, updates 14-day baselines, evaluates Readiness and Sleep scores, attributes to morning wake-up date (`YYYY-MM-DD`, DEC-016), and persists `DailyEvaluationRecord`.
* **Verified with automated test suite:** **44 tests passed, 0 failures**.

### ✅ Phase 6: Edge AI Engine Integration (COMPLETED)
* **Swift 6 Strict Concurrency Architecture (`OpenRingAI`):** Built fully isolated edge inference subsystem using native actors (`MockInferenceBackend`, `LlamaCppBackend`, `LLMInferenceService`).
* **Non-Diagnostic Sports Science System Prompt (DEC-005, DEC-012):** Deterministic Llama-3.2 instruct template comparing nightly resting heart rate, HRV rMSSD, total sleep, deep sleep, REM sleep, thermal deviation, and scores against 14-day baselines in a structured markdown table. Enforces a strict 3-paragraph format under 140 words.
* **Foreground Jetsam Defense Gate (DEC-007, DEC-017):** Strict application lifecycle check (`isForeground`) preventing memory allocation or model loading in the background, safeguarding against iOS 30–60 MB Jetsam eviction.
* **Dual-Backend Support (DEC-017):**
  * `LlamaCppBackend`: Metal GPU-accelerated execution of bundled `Llama-3.2-3B-Instruct-Q4_K_M.gguf` with file integrity and minimum size checks.
  * `MockInferenceBackend`: Hermetic, sub-second token streaming actor for offline CI environments.
* **Automated SQLite WAL Persistence:** Live token streaming via `AsyncStream<String>` with automatic commitment to `DailyEvaluationRecord.aiSynthesisMarkdown` upon completion.
* **Model Download Automation:** Provided [`scripts/download_model.sh`](scripts/download_model.sh) for resumable acquisition of the 4-bit quantized GGUF model weights (~1.45 GB).
* **Verified with automated test suite:** **51 tests passed, 0 failures (7 Phase 6 tests)**.

### ✅ Phase 7: Native SwiftUI Views & Interactive 60 FPS Charts (COMPLETED)
* **Modular Packaging Architecture (DEC-018):** Separated presentation into dedicated `OpenRingUI` library target in `Package.swift` and thin `OpenRingApp` executable wrapper launching `@main struct OpenRingApp: App`.
* **4-Tab Navigation Shell (`MainTabView`):**
  * **Tab 1: Readiness Dashboard (`ReadinessDashboardView`):** Circular score gauge ($0–100$), biometric delta cards comparing against 14-day rolling baselines (RHR, HRV rMSSD, sleep efficiency, thermal deviation), and live BLE status/battery header.
  * **Tab 2: Sleep Architecture (`SleepArchitectureView`):** 60 FPS interactive hypnogram chart (SwiftUI `Charts`) with stage scrubbing across Awake, REM, Light, and Deep stages, stage percentage cards, and deterministic Sleep Score ($0–100$, DEC-016).
  * **Tab 3: Edge AI Recovery Coach (`RecoveryCoachView`):** Live streaming typewriter card rendering on-device Llama-3.2-3B recovery syntheses, formatted across 3 structured paragraphs (*Autonomic Load*, *Sleep Architecture*, *Actionable Protocol*) under 140 words, with an FDA SaMD non-diagnostic disclaimer.
  * **Tab 4: Settings & Data Sovereignty (`SettingsView` - Combined Hub):**
    * Ring hardware pairing & BLE connection status.
    * Active AES-128 secret key hex viewer, 16-byte random key generator, and manual hex key import.
    * Zero-telemetry audit confirmation (air-gapped sandbox verification with 0 network sockets).
    * SQLite WAL database statistics (sample counts, episode counts, file size in KB).
    * Full data portability with 1-tap raw export to CSV and JSON.
    * Community credits, GPLv3 terms with App Store exception, and v2 AI model swapping hook.
* **Adaptive Dynamic Theming (DEC-018):** Automatically adapts between Apple Light Mode and Dark Mode using semantic system colors, with standardized physiological recovery palette (Emerald, Sky Blue, Amber, Coral).
* **Direct Hardware Data Binding:** Clean empty states prompting pairing when uninitialized without synthetic demo toggles.
* **Verified with automated test suite:** **56 tests passed, 0 failures (5 Phase 7 tests)**.

---

## Deterministic Physiological Formulations

OpenRing computes all wellness scores locally and deterministically using sports science principles and Apple Accelerate (`vDSP`):

### 1. HRV (rMSSD) Calculation
Given artifact-filtered inter-beat intervals $IBI = [x_1, x_2, \dots, x_N]$ in milliseconds:
$$\text{rMSSD} = \sqrt{\frac{1}{N-1}\sum_{i=1}^{N-1}(x_{i+1} - x_i)^2}$$
* **Physiological Rejection:** Beats $x_i < 350\text{ ms}$ (~171 bpm) or $x_i > 1800\text{ ms}$ (~33 bpm), as well as inter-beat jumps $|x_{i+1} - x_i| > 300\text{ ms}$, are filtered out as motion artifacts or ectopic beats.

### 2. 14-Day Rolling Exponential Moving Average (EMA)
$$\text{Baseline}_t = \alpha \cdot \text{DailyValue}_t + (1 - \alpha) \cdot \text{Baseline}_{t-1}, \quad \text{where } \alpha = \frac{2}{N + 1} = \frac{2}{15} \approx 0.1333$$

### 3. Deterministic Sleep Score ($S_{\text{sleep}} \in [0, 100]$)
Based on polysomnography and sleep hygiene standards:
$$S_{\text{sleep}} = P_{\text{duration}} + P_{\text{efficiency}} + P_{\text{deep}} + P_{\text{rem}}$$
* **Total Duration ($P_{\text{duration}} \in [0, 35]$):** Scales linearly up to 7–9 hours (420–540 minutes). Full 35 points at $\ge 7\text{ hours}$; scales proportionally below.
* **Sleep Efficiency ($P_{\text{efficiency}} \in [0, 30]$):** Ratio of total sleep time to time in bed. Full 30 points at $\ge 85\%$; scales down linearly below $85\%$.
* **Deep Sleep ($P_{\text{deep}} \in [0, 20]$):** Target $\ge 1.5\text{ hours}$ (or $\ge 15–20\%$ of total sleep). Full 20 points at $\ge 90\text{ minutes}$.
* **REM Sleep ($P_{\text{rem}} \in [0, 15]$):** Target $\ge 1.5\text{ hours}$ (or $\ge 20–25\%$ of total sleep). Full 15 points at $\ge 90\text{ minutes}$.

### 4. Deterministic Readiness Score ($S_{\text{readiness}} \in [0, 100]$)
$$S_{\text{readiness}} = 100 - \left(0.35 \cdot \Delta RHR + 0.35 \cdot \Delta HRV + 0.15 \cdot \Delta Temp + 0.15 \cdot (100 - E_{\text{sleep}})\right)$$
* $\Delta RHR = \max\left(0, \frac{RHR_{\text{night}} - RHR_{\text{baseline}}}{RHR_{\text{baseline}}}\right) \times 100$
* $\Delta HRV = \max\left(0, \frac{HRV_{\text{baseline}} - HRV_{\text{night}}}{HRV_{\text{baseline}}}\right) \times 100$
* $\Delta Temp = \max\left(0, \frac{T_{\text{deviation}} - 0.50^\circ\text{C}}{0.10^\circ\text{C}}\right) \times 10$
* $E_{\text{sleep}} = \text{SleepEfficiencyPercentage } (0 - 100\%)$

### 5. Daily Evaluation Attribution
Sleep episodes concluding in the morning (between 04:00 and 14:00) are assigned to the **wake-up date** (`YYYY-MM-DD`), aligning recovery scores with the morning the user wakes up.

---

## Repository Structure

```
openring/
├── README.md                             # Project overview & status
├── Decisions Log.md                      # Architecture Decision Records (DEC-001 - DEC-018)
├── Implementation Plan.md                # 8-Phase implementation roadmap & specs
├── OpenRing App Engineering Docs.md      # Unified PRD & Technical Design Document
├── Package.swift                         # Swift 6 package manifest
├── scripts/
│   └── download_model.sh                 # Resumable curl download for Llama-3.2-3B GGUF weights
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
│   ├── OpenRingStorage/                  # Native SQLite WAL persistence & evaluation pipeline
│   │   ├── DatabaseService.swift         # Thread-safe SQLite actor & prepared statement range queries
│   │   ├── Models.swift                  # Pure Swift 6 records (Sendable, Codable, Equatable)
│   │   ├── SyncCoordinator.swift         # BLE event ingestion actor & lossless raw archiver
│   │   └── DailyEvaluationEngine.swift   # Post-sleep biometric aggregator & baseline pipeline
│   ├── OpenRingAI/                       # Edge AI inference engine & non-diagnostic prompt pipeline
│   │   ├── Backend/
│   │   │   ├── InferenceBackend.swift    # Abstract backend protocol & InferenceError enum
│   │   │   ├── MockInferenceBackend.swift# Hermetic token streaming actor for sub-second offline testing
│   │   │   └── LlamaCppBackend.swift     # Metal GPU accelerated llama.cpp runner for GGUF weights
│   │   ├── Prompt/
│   │   │   └── PromptBuilder.swift       # Llama-3.2 instruct template & biometric table formatter
│   │   └── Service/
│   │       └── LLMInferenceService.swift # Foreground Jetsam defense gate & SQLite auto-persistence
│   ├── OpenRingUI/                       # Native SwiftUI Views, ViewModels, Theme & 60 FPS Charts
│   │   ├── Theme/
│   │   │   └── Theme.swift               # Semantic light/dark surfaces & physiological recovery palette
│   │   ├── Components/
│   │   │   ├── ScoreGaugeView.swift      # Animated circular score gauge (0-100)
│   │   │   ├── MetricDeltaCard.swift     # 14-day baseline biometric comparison cards
│   │   │   ├── HypnogramChartView.swift  # Interactive 60 FPS hypnogram chart (SwiftUI Charts)
│   │   │   └── TypewriterTextCard.swift  # Streaming token card with non-diagnostic footer
│   │   ├── ViewModels/
│   │   │   ├── DashboardViewModel.swift  # Tab 1 MainActor ViewModel
│   │   │   ├── SleepViewModel.swift      # Tab 2 MainActor ViewModel
│   │   │   ├── CoachViewModel.swift      # Tab 3 MainActor ViewModel
│   │   │   └── SettingsViewModel.swift   # Tab 4 MainActor ViewModel (Settings + Sovereignty)
│   │   └── Views/
│   │       ├── ReadinessDashboardView.swift # Tab 1 View
│   │       ├── SleepArchitectureView.swift  # Tab 2 View
│   │       ├── RecoveryCoachView.swift      # Tab 3 View
│   │       ├── SettingsView.swift           # Tab 4 View (Settings, Sovereignty & Portability)
│   │       └── MainTabView.swift            # Root 4-tab container
│   ├── OpenRingApp/                      # Application entry point
│   │   └── OpenRingApp.swift             # @main struct OpenRingApp: App initializing actors
│   ├── OpenRingMock/                     # Virtual peripheral & synthetic telemetry generator
│   │   ├── MockDataGenerator.swift       # Full night session stream generator
│   │   └── OuraRingMock.swift            # CBPeripheralManager GATT simulator
│   └── MockRunner/
│       └── main.swift                    # CLI executable to run the mock ring on macOS
└── Tests/
    ├── OpenRingCoreTests/                # Unit test suites for protocol, crypto, decoders, DSP
    ├── OpenRingMockTests/                # Tests for synthetic data & mock peripheral
    ├── OpenRingStorageTests/             # Tests for SQLite tables, range queries, ingestion
    ├── OpenRingAITests/                  # Tests for edge AI engine, Jetsam gates, prompt tables
    ├── OpenRingUITests/                  # Tests for UI ViewModels, stage heuristics & data portability
    └── TestRunner/
        └── main.swift                    # Consolidated test executor
```

---

## Quick Start & Verification

### Prerequisites
* macOS 14.0+
* Swift 6.0+ (Command Line Tools or Xcode 16+)

### Run Automated Tests
To build and execute the full test suite verifying framing, AES-128 cryptography, event decoders, DSP algorithms, SQLite WAL persistence, evaluation pipelines, and edge AI inference:

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

# 3. Compile OpenRingStorage library
swiftc -module-cache-path .build/cache -I .build -L .build -lOpenRingCore -lsqlite3 \
  -parse-as-library Sources/OpenRingStorage/*.swift \
  -emit-library -module-name OpenRingStorage -o .build/libOpenRingStorage.dylib

# 4. Compile OpenRingAI library
swiftc -module-cache-path .build/cache -I .build -L .build -lOpenRingCore -lOpenRingStorage -lsqlite3 \
  -parse-as-library Sources/OpenRingAI/Backend/*.swift Sources/OpenRingAI/Prompt/*.swift Sources/OpenRingAI/Service/*.swift \
  -emit-library -module-name OpenRingAI -o .build/libOpenRingAI.dylib

# 5. Compile OpenRingUI library
swiftc -module-cache-path .build/cache -I .build -L .build -lOpenRingCore -lOpenRingStorage -lOpenRingAI -lsqlite3 \
  -parse-as-library Sources/OpenRingUI/Theme/*.swift Sources/OpenRingUI/Components/*.swift Sources/OpenRingUI/ViewModels/*.swift Sources/OpenRingUI/Views/*.swift \
  -emit-library -module-name OpenRingUI -o .build/libOpenRingUI.dylib

# 6. (Optional) Compile OpenRingApp standalone binary
swiftc -module-cache-path .build/cache -parse-as-library \
  -I .build -L .build -lOpenRingCore -lOpenRingStorage -lOpenRingAI -lOpenRingUI -lsqlite3 \
  Sources/OpenRingApp/OpenRingApp.swift -o .build/OpenRingApp

# 7. Execute consolidated test suite
DYLD_LIBRARY_PATH=.build swift -module-cache-path .build/cache \
  -I .build -L .build -lOpenRingCore -lOpenRingMock -lOpenRingStorage -lOpenRingAI -lOpenRingUI -lsqlite3 \
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
  ✅ [PASS] Sleep score mathematical bounds and component weights (DEC-016)
  ✅ [PASS] Open heuristic sleep stage fallback classifier (DEC-011)
  ✅ [PASS] 14-day EMA multi-day convergence progression

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

--- [7] Local Storage Engine (SQLite WAL) & Range Queries ---
  ✅ [PASS] DatabaseService in-memory initialization and schema migration
  ✅ [PASS] DatabaseService disk initialization with WAL mode pragmas
  ✅ [PASS] Raw packet ingestion audit logging
  ✅ [PASS] Batch save and range query biometric samples
  ✅ [PASS] Save and range query temperature telemetry
  ✅ [PASS] Save and query sleep episodes
  ✅ [PASS] Save and query daily evaluations
  ✅ [PASS] Idempotency and update verification (INSERT OR REPLACE)
     ⚡ 30-day range query (8,640 samples) completed in 0.76 ms (Target: < 10.0 ms)
  ✅ [PASS] Performance Benchmark: 30-day range query latency (<10ms target)

--- [8] SyncCoordinator Event Ingestion Pipeline ---
  ✅ [PASS] SyncCoordinator ingests single events and updates state
  ✅ [PASS] SyncCoordinator ingests full synthetic night (252 events)
  ✅ [PASS] SyncCoordinator stream subscription lifecycle

--- [9] DailyEvaluationEngine & End-to-End Evaluation Pipeline ---
  ✅ [PASS] DatabaseService targeted queries for evaluations and sleep sessions
  ✅ [PASS] DailyEvaluationEngine correlates biometrics, temperature, and computes scores
  ✅ [PASS] DailyEvaluationEngine multi-day baseline tracking across consecutive nights
  ✅ [PASS] End-to-End Pipeline: Synthetic night ingestion automatically evaluates scores and baselines in SQLite

--- [10] Edge AI Engine (LLMInferenceService & Prompt Pipeline) ---
  ✅ [PASS] PromptBuilder formats valid Llama-3.2 instruct template with biometric table
  ✅ [PASS] PromptBuilder system prompt enforces non-diagnostic constraints and 3-paragraph format
  ✅ [PASS] MockInferenceBackend lifecycle management
  ✅ [PASS] LLMInferenceService foreground Jetsam safety gate
  ✅ [PASS] LLMInferenceService token streaming and output formatting (<140 words, 3 paragraphs)
  ✅ [PASS] End-to-End Edge AI Synthesis Pipeline with SQLite WAL
  ✅ [PASS] LlamaCppBackend weight file validation

--- [11] Native SwiftUI ViewModels & Presentation Logic ---
  ✅ [PASS] Theme physiological recovery palette and tier title mapping
  ✅ [PASS] DashboardViewModel empty state and live evaluation binding
  ✅ [PASS] SleepViewModel episode parsing, hypnogram generation, and heuristic staging
  ✅ [PASS] CoachViewModel synthesis state transitions and streaming consumption
  ✅ [PASS] SettingsViewModel key management, validation, and zero-telemetry export

==================================================
 Test Results: 56 Passed, 0 Failed
==================================================
```

### Download Quantized Model Weights (Physical Device Inference)
The unit test suite runs completely hermetically and offline in sub-second time using `MockInferenceBackend` without needing the model weights. For running Metal GPU inference on physical Apple Silicon hardware:

```bash
chmod +x scripts/download_model.sh
./scripts/download_model.sh
```
This downloads `Llama-3.2-3B-Instruct-Q4_K_M.gguf` (~1.45 GB) into the `Models/` directory via resumable `curl`.
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

* [**`TESTING_WITH_RING.md`**](TESTING_WITH_RING.md): Comprehensive step-by-step physical ring testing protocol on iPhone (pairing, sync, tab verification, troubleshooting).
* [**`RELEASE_v0.1.md`**](RELEASE_v0.1.md): Formal v0.1 release notes, architecture summary, and test suite results.
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

