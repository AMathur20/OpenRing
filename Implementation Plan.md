# Phased Implementation Plan: OpenRing Native iOS Client

OpenRing is an offline, zero-telemetry, local-first mobile client for Oura Ring hardware (primarily Gen 3) built natively in Swift 6 and SwiftUI. It directly communicates with the ring over Bluetooth Low Energy (BLE), persists telemetry to a local SQLite database via GRDB.swift (WAL mode), processes biometric time series with deterministic DSP pipelines (rMSSD, RHR, nocturnal temperature, sleep stages), and generates offline athletic/wellness recovery summaries using an on-device 4-bit quantized Llama-3.2-3B model.

---

## User Review Required

> [!IMPORTANT]
> **Phase 1 Priority: Clarifications on Proprietary Protocols & Hardware Access**
> Building a functional offline client for proprietary hardware requires specific binary protocol definitions and hardware/simulation environments. The questions below must be resolved to ensure clean implementation without guesswork.

> [!WARNING]
> **Proprietary Cryptographic Handshake & Sensor Payload Schemas**
> While `OpenRing App Engineering Docs.md` outlines the high-level packet structure (SOF 0xAA, CRC-16, Sequence numbers) and GATT UUIDs, the internal sensor-specific payloads (Packet Types 0x01–0x04) and the cryptographic handshake (Opcodes 0x0C, 0x0D, 0x0E) require precise specifications or sample packet captures.

---

## Phase 1: Specifications & Protocol Clarifications (COMPLETED)

Based on reverse-engineering analysis of physical Oura Ring (Gen 3 Horizon & Ring 5) communications in `Th0rgal/open_oura`:

### 1. BLE Protocol & Cryptographic Handshake
* **GATT Service:** `98ed0001-a541-11e4-b6a0-0002a5d5c51b`
* **Characteristics:**
  * Write: `98ed0002-a541-11e4-b6a0-0002a5d5c51b`
  * Notify: `98ed0003-a541-11e4-b6a0-0002a5d5c51b`
* **Cryptographic Handshake:**
  * Request Nonce: Central writes `[0x2f, 0x01, 0x2b]` to `98ed0002`.
  * Ring responds on `98ed0003` with a 15-byte challenge nonce.
  * Algorithm: **AES-128 / ECB mode with PKCS#7 padding** under a shared 16-byte key.
  * Auth Response: Central writes `[0x2f, 0x11, 0x2d, <16-byte ciphertext>]`.
  * Ring returns Status `0x00` (Success).
* **Key Provisioning:**
  * For a factory-reset ring: Central generates a random 16-byte key, writes `Packet(0x24, key)`, and saves it locally.
  * For pre-paired rings: User inputs their 16-byte hex key.
* **Time Sync:** Packet `0x12` with 8-byte LE Unix timestamp and timezone offset.

### 2. Sensor Payload Binary Formats & Event Tag Mapping
* **Packet Framing:** `[Tag: 1 byte, Declared Length: 1 byte, Payload: Length bytes]`.
* **History Events:** Tags $\ge 0x41$. Each history event begins with a 4-byte LE decisecond timestamp followed by the event body.
  * **Tag `0x5D` (`hrv_event`):** Consecutive pairs of `(avg HR bpm: u8, avg RMSSD ms: u8)` per 5-minute interval.
  * **Tags `0x46`, `0x69`, `0x75` (`temp_event`, `temp_period`, `sleep_temp`):** Series of `i16` LE centi-°C ($\text{temp} = \text{val} / 100.0\,^\circ\text{C}$).
  * **Tags `0x44`, `0x60`, `0x80` (`ibi_event`, `ibi_and_amplitude`, `green_ibi_quality`):** Inter-beat interval (ms) streams with validity/quality bits.
  * **Tags `0x47`, `0x6B`, `0x72` (`motion_event`, `motion_period`, `sleep_acm_period`):** Accelerometer 3-axis vectors and MAD motion intensity.
  * **Tags `0x6F`, `0x70` (`spo2_event`):** SpO2 optical percentages.

### 3. Sleep Stage Staging (Hardware Hypnogram)
* The Oura Ring Gen 3 firmware **computes sleep stages directly on-device**:
  * Tags **`0x4B`**, **`0x4E`**, and **`0x5A`** stream 2-bit hypnogram stage codes: `DEEP`, `LIGHT`, `REM`, `AWAKE` (4 samples packed per byte).
  * Tags **`0x49`**, **`0x4C`**, **`0x4F`**, **`0x58`** emit sleep summaries (bedtime, stage durations, lowest HR).
  * An open heuristic fallback will be implemented for gaps in firmware reports.

### 4. Hardware & Testing Strategy
* **Physical Hardware:** Physical Oura Ring Gen 3 and iPhone 16 (Apple A18, 8 GB RAM) available for end-to-end device testing.
* **Mock Peripheral:** Virtual BLE mock peripheral (`OuraRingMock`) will be built to allow rapid macOS and Simulator testing without requiring physical ring wear.


---

## Phased Implementation Roadmap

Once the open questions in Phase 1 are clarified, the development of OpenRing will proceed through the following successive phases:

```
+-------------------------------------------------------------------------------+
| Phase 1: Discovery, Specifications & Protocol Clarification (COMPLETED)       |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 2: Project Scaffolding, Core Architecture & BLE Mock Environment (DONE) |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 3: CoreBluetooth Engine & Frame Reassembly Actor (COMPLETED)            |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 4: Local Storage Engine (Native SQLite3 WAL Mode) (COMPLETED)           |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 5: Deterministic DSP & Biometric Evaluation Pipelines (COMPLETED)       |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 6: Edge AI Engine Integration (llama.cpp Metal & Bundled Model) (DONE)  |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 7: Native SwiftUI Views & Interactive 60 FPS Charts (COMPLETED)         |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 8: Background State Restoration, Jetsam Hardening & Audit [NEXT UP]     |
+-------------------------------------------------------------------------------+
```

### Phase 2: Project Scaffolding, Core Architecture & BLE Mock Environment (COMPLETED)
- Initialized native iOS Swift 6 library with strict concurrency.
- Built `OpenRingCore`, `OpenRingStorage`, and `OpenRingMock` targets.
- Implemented `PacketReassemblyEngine`, `SignalProcessor`, and `OuraRingMock`.

### Phase 3: CoreBluetooth Engine & Frame Reassembly Actor (COMPLETED)
- Implemented `BLEEngine` as an isolated Swift 6 `actor`:
  - `CBCentralManager` state management (discovery, connection, MTU negotiation).
  - Background state restoration handling via `centralManager(_:willRestoreState:)`.
  - GATT service (`98ed0001`) and characteristic (`98ed0002` write, `98ed0003` notify) discovery and notification subscription.
  - Automated cryptographic session handshake handler (AES-128-ECB PKCS#7 challenge-response).
  - Non-isolated `states`, `events`, and `discoveredRings` asynchronous streams (`AsyncStream`).
  - History dump (`reqGetEvents`), time sync (`reqSyncTime`), and battery (`reqBattery`) command dispatches.
  - Direct pipeline into `PacketReassemblyEngine` yielding typed `RingEvent` streams.
- Verified with unit and state machine tests: 25/25 passing tests (including challenge nonce handling, auth success/failure transitions, and live telemetry streaming).

### Phase 4: Local Storage Engine & SyncCoordinator Pipeline (COMPLETED)
- Implemented `DatabaseService` actor using native `SQLite3` in WAL mode (`PRAGMA journal_mode = WAL`):
  - In-memory (`:memory:`) mode for isolated high-speed hermetic tests.
  - Disk mode (`openring.sqlite` in Application Support) for production persistence.
  - Enforced pragmas: `journal_mode = WAL`, `synchronous = NORMAL`, `foreign_keys = ON`, `busy_timeout = 5000`.
  - Schema migrations (`v1_initial_schema`):
    - `raw_ingestion_log`: Audit trail of all deframed BLE packets (`id`, `receivedTimestamp`, `packetType`, `sequenceId`, `framePayload`).
    - `biometric_samples`: 5-minute time-series (`timestamp`, `heartRateBpm`, `rmssdMs`, `motionIntensity`, `ppgSignalQuality`).
    - `temperature_telemetry`: Nocturnal temperature offsets (`timestamp`, `rawCelsius`, `baselineOffsetCelsius`).
    - `sleep_episodes`: Sleep sessions and classified stages (`sessionId`, `startTime`, `endTime`, durations, metrics).
    - `daily_evaluations`: Computed readiness, sleep scores, baselines, and AI summaries (`evaluationDate`, scores, baselines, LLM markdown).
  - High-performance range query methods with SQLite prepared statements:
    - Benchmark achieved: 30-day range query ($8,640$ 5-minute samples) executed in **0.82 ms** (Target: $<10\text{ ms}$).
- Implemented `SyncCoordinator` actor in `OpenRingStorage`:
  - Bridges `BLEEngine.events: AsyncStream<RingEvent>` into `DatabaseService`.
  - Converts decisecond ring timestamps to Unix epoch milliseconds.
  - Maps `.hrv`, `.temperature`, `.sleepPhases` into typed records.
  - Lossless raw logging into `raw_ingestion_log`.
  - Transaction-batched persistence for high throughput (full 252-event night ingested in $<15\text{ ms}$).
- Verified with comprehensive test suite: **37/37 passing tests**.


### Phase 5: Deterministic DSP & Biometric Evaluation Pipelines (COMPLETED)
- Implemented `SignalProcessor` in `OpenRingCore` using Apple `Accelerate` (`vDSP`):
  - Artifact rejection ($|x_{i+1} - x_i| > 300\text{ms}$ or $x_i \notin [350, 1800]\text{ms}$) with vector-accelerated `vDSP_meanvD`.
  - Rolling 14-day exponential moving averages (EMA) for RHR, HRV, and temperature baselines ($\alpha = 2/15 \approx 0.1333$).
  - Polysomnography-aligned Sleep Score formula (DEC-016): duration 35, efficiency 30, deep 20, REM 15.
  - Deterministic Readiness Score computation:
    $$S_{\text{readiness}} = 100 - (0.35\Delta RHR + 0.35\Delta HRV + 0.15\Delta Temp + 0.15(100 - E_{\text{sleep}}))$$
  - Open heuristic sleep stage fallback classifier (`classifySleepStageHeuristic` and batch `classifySleepStagesHeuristic`, DEC-011).
- Implemented `DailyEvaluationEngine` actor in `OpenRingStorage`:
  - Correlates nocturnal biometric samples and temperature telemetry with sleep episodes.
  - Updates `SleepEpisodeRecord` with nocturnal lowest HR, average HR, average RMSSD, and temperature deviation.
  - Evaluates Sleep and Readiness scores against 14-day EMA baselines with morning wake-up date attribution (`YYYY-MM-DD`, DEC-016).
  - Persists `DailyEvaluationRecord` in SQLite.
- Enhanced `DatabaseService` with targeted query methods:
  - `fetchDailyEvaluation(for:)`, `fetchLatestDailyEvaluation(before:)`, `fetchSleepEpisode(sessionId:)`, `fetchLatestSleepEpisode()`.
- Integrated automated evaluation into `SyncCoordinator`:
  - Consolidates streaming 5-minute epochs into contiguous sleep sessions.
  - Automatically triggers post-sleep evaluation upon batch sync completion.
- Verified with automated test suite: **44/44 passing tests**.

### Phase 6: Edge AI Engine Integration (llama.cpp Metal & Bundled Llama-3.2-3B) (COMPLETED)
- Implemented `OpenRingAI` module with Swift 6 strict concurrency (`-strict-concurrency=complete`):
  - **`InferenceBackend` Protocol:** Sendable abstraction (`isLoaded`, `modelTag`, `loadModel(at:)`, `unloadModel()`, `generate(prompt:maxTokens:) -> AsyncStream<String>`).
  - **`PromptBuilder` Pipeline:**
    - Deterministic Llama-3.2 instruct template with special tokens (`<|begin_of_text|>`, `<|start_header_id|>`, etc.).
    - Strictly non-diagnostic system prompt enforcing functional sports science framing (DEC-005) and 3-paragraph format under 140 words.
    - Structured biometric status markdown table comparing nightly resting heart rate, HRV rMSSD, total sleep, deep sleep, REM sleep, thermal deviation, Readiness score, and Sleep score against 14-day rolling baselines.
  - **`MockInferenceBackend` Actor:** Deterministic token stream generator for sub-second, hermetic CI/unit testing (DEC-017).
  - **`LlamaCppBackend` Actor:** Direct integration layer for Metal GPU-accelerated GGUF inference on Apple Silicon with weight file validation.
  - **`LLMInferenceService` Actor:**
    - Lifecycle management for model initialization, unloading, and active busy state tracking.
    - **Foreground Jetsam Defense Gate (DEC-007, DEC-017):** Checks application lifecycle (`isForeground`). Immediately rejects inference with `InferenceError.backgroundExecutionBlocked` if triggered during background execution.
    - Live token streaming via Swift `AsyncStream<String>`.
    - Automated persistence to SQLite WAL: commits completed synthesis markdown directly to `DailyEvaluationRecord.aiSynthesisMarkdown` in `DatabaseService`.
- Created automated download helper script: [`scripts/download_model.sh`](file:///Users/ankurmathur/Documents/openring/scripts/download_model.sh) to fetch `Llama-3.2-3B-Instruct-Q4_K_M.gguf` via resumable `curl`.
- Verified with automated test suite: **51/51 passing tests (7 Phase 6 tests)**.

### Phase 7: Native SwiftUI Views & Interactive 60 FPS Charts (COMPLETED)
- **Modular Packaging Architecture (DEC-018):**
  - Implement `OpenRingUI` library target in `Package.swift` (dependent on `OpenRingCore`, `OpenRingStorage`, `OpenRingAI`).
  - Implement `OpenRingApp` executable wrapper launching `@main struct OpenRingApp: App`.
- **4-Tab Navigation Shell (`MainTabView`):**
  - **Tab 1: Readiness (`ReadinessDashboardView`):** Radial readiness score gauge ($0–100$), sub-score metrics (RHR delta, HRV rMSSD % delta, sleep efficiency, temperature deviation), 14-day rolling baseline comparisons, and live BLE status/battery header.
  - **Tab 2: Sleep (`SleepArchitectureView`):** 60 FPS interactive hypnogram chart (SwiftUI `Charts`) with stage scrubbing across Awake, REM, Light, and Deep stages, stage duration metrics, and Sleep Score ($0–100$).
  - **Tab 3: Recovery (`RecoveryCoachView`):** Typewriter token streaming card for on-device Llama-3.2-3B recovery synthesis, structured 3-paragraph display (*Autonomic Load*, *Sleep Architecture*, *Actionable Recovery Protocol*), and FDA SaMD non-diagnostic disclaimer.
  - **Tab 4: Settings (`SettingsView` - Combined Hub):**
    - Ring hardware & pairing: BLE state, discovery/connection, RSSI, and battery telemetry.
    - Security & Keys: Active AES-128 key hex, 16-byte key import, and factory pairing reset.
    - Data Sovereignty Audit: Zero-telemetry validation badge, air-gapped sandbox verification (0 network sockets), and SQLite WAL database stats.
    - Data Portability: Raw SQL export of biometric samples, temperature series, and sleep sessions to CSV/JSON format.
    - Community & Credits: `open_oura` and `llama.cpp` acknowledgments, GNU GPLv3 terms, and Apple App Store / Google Play exception details.
    - Feedback & Diagnostics: Local offline log browser.
    - v2 Extension Hook: AI model selection placeholder for future GGUF swapping.
  - *(Roadmap: A 5th tab dedicated to **Workout Tracking** is planned for v2.0).*
- **Adaptive Semantic Theming (DEC-018):**
  - Automatically adapt between Apple Light Mode and Dark Mode using system semantic colors (`systemBackground`, `secondarySystemGroupedBackground`, etc.).
  - Color-code recovery states: Emerald (optimal), Sky Blue (nominal), Amber (strain), Coral (recovery needed).
- **Direct Hardware Data Binding:**
  - Binds directly to `DatabaseService` and `BLEEngine` without synthetic demo toggles.
  - Graceful empty states prompting pairing when uninitialized.
- **Verified with automated test suite:** **56 tests passed, 0 failures (5 Phase 7 tests)**.

### Phase 8: Background Ingestion, Reliability & App Store Hardening [NEXT UP]
- Implement iOS background execution handler:
  - Background fetch / BLE background state restoration within 30-second window.
  - Pointer-safe ACK protocol (advancing flash pointer only after verified DB commit).
  - Memory containment test: ensuring memory remains strictly $\le 30-60\text{MB}$ in background.
- Enforce network sandboxing: verify binary has zero network entitlement or outgoing sockets.
- App Store Guideline 1.4.1 & FDA SaMD compliance verification audit (ensuring zero clinical diagnostic claims).

---

## Verification Plan

### Automated Tests
- **Packet Reassembly & CRC Suite:** Unit tests feeding fragmented, corrupted, and out-of-order byte streams into `PacketReassemblyEngine`.
- **DSP Math & Readiness Formulas:** Verification against known reference data sets for rMSSD, EMA calculation, and readiness score bounds ($[0, 100]$).
- **Database Performance Benchmarks:** Ingest 100,000 synthetic biometric samples into SQLite WAL and assert range query execution time $< 10\text{ms}$.
- **Memory Pressure Tests:** Measure active physical RAM during Llama-3.2-3B inference to ensure peak consumption stays $\le 1.5\text{GB}$.

### Manual & Integration Verification
- **BLE Mock Simulation:** Verify end-to-end sync, decoding, database persistence, and UI rendering using the virtual peripheral harness.
- **Physical Ring Testing (when available):** Test discovery, bonding, flash circular buffer draining, and reconnection reliability with an Oura Ring Gen 3.
- **Background Sync Lifecycle:** Trigger background suspension via Xcode debug gauges and verify successful resumption without jetsam SIGKILL.

