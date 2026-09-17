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
| Phase 1: Discovery, Specifications & Protocol Clarification (CURRENT)         |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 2: Project Scaffolding, Core Architecture & BLE Mock Environment        |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 3: CoreBluetooth Engine & Frame Reassembly Actor                        |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 4: Local Storage Engine (GRDB.swift / SQLite WAL Mode)                  |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 5: Deterministic DSP & Biometric Evaluation Pipelines                  |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 6: Edge AI Engine Integration (Quantized Llama-3.2-3B)                  |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 7: Native SwiftUI Views & Interactive 60 FPS Charts                     |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼
+-------------------------------------------------------------------------------+
| Phase 8: Background State Restoration, Jetsam Hardening & App Store Audit     |
+-------------------------------------------------------------------------------+
```

### Phase 2: Project Scaffolding, Core Architecture & BLE Mock Environment
- Initialize native iOS Swift 6 project structure with strict concurrency checking enabled (`-strict-concurrency=complete`).
- Configure package dependencies via Swift Package Manager:
  - `GRDB.swift` (persistence)
  - Inference dependencies (`llama.cpp` Swift package or CoreML runtime)
- Build a **BLE Mock Peripheral & Telemetry Harness** (`OuraRingMock`):
  - Simulates the Oura Control Service (`0x9E5D0E00`) and Data Stream Service (`0x9E5D0E10`).
  - Generates realistic raw binary frames (SOF `0xAA`, sequence IDs, CRC-16-CCITT) to facilitate headless unit testing and Simulator development without requiring a physical ring 100% of the time.

### Phase 3: CoreBluetooth Engine & Frame Reassembly Actor
- Implement `BLEEngine` as an isolated Swift 6 `actor`:
  - `CBCentralManager` state management (discovery, connection, MTU negotiation to 244 bytes).
  - Background state restoration handling via `centralManager(_:willRestoreState:)`.
  - GATT service and characteristic discovery and notification configuration.
  - Cryptographic session handshake handler.
- Implement and unit-test `PacketReassemblyEngine` actor:
  - Byte sliding window buffer.
  - SOF (`0xAA`) scanning and synchronization recovery.
  - CRC-16-CCITT calculation ($P(x) = x^{16} + x^{12} + x^5 + 1$).
  - Missing sequence gap detection.

### Phase 4: Local Storage Engine (GRDB.swift / SQLite WAL Mode)
- Implement `DatabaseService` actor managing a thread-safe SQLite connection pool in WAL mode.
- Execute schema migrations for:
  - `raw_ingestion_log`: Immutable audit log of received BLE frames.
  - `biometric_samples`: 5-minute parsed samples (HR, rMSSD, motion, signal quality).
  - `temperature_telemetry`: Nocturnal temperature offsets.
  - `sleep_episodes`: Sleep sessions and classified stages.
  - `daily_evaluations`: Computed readiness, sleep scores, baselines, and AI summaries.
- Implement high-performance range query methods (<10ms target for 30-day lookups).

### Phase 5: Deterministic DSP & Biometric Evaluation Pipelines
- Implement `SignalProcessor` using Apple `Accelerate` (`vDSP`):
  - Artifact rejection ($|x_{i+1} - x_i| > 300\text{ms}$ or $x_i \notin [350, 1800]\text{ms}$).
  - Rolling 5-minute rMSSD calculation:
    $$\text{rMSSD} = \sqrt{\frac{1}{N-1}\sum_{i=1}^{N-1}(x_{i+1}-x_i)^2}$$
  - 14-day exponential moving averages (EMA) for RHR, HRV, and temperature.
  - Deterministic Readiness Score computation:
    $$S_{\text{readiness}} = 100 - (0.35\Delta RHR + 0.35\Delta HRV + 0.15\Delta Temp + 0.15(100 - E_{\text{sleep}}))$$
  - Sleep stage classifier heuristic/statistical engine.

### Phase 6: Edge AI Engine Integration (llama.cpp Metal & Bundled Llama-3.2-3B)
- Integrate `llama.cpp` via Swift Package Manager with Metal GPU backend.
- Bundle `Llama-3.2-3B-Instruct-Q4_K_M.gguf` (~1.45 GB) directly in the app bundle (with an architecture ready for v2 custom model swapping).
- Implement `LLMInferenceService` actor:
  - Model lifecycle management (lazy instantiation, unloading under memory warnings).
  - Prompt construction with structured biometric markdown tables.
  - Strictly non-diagnostic functional wellness system prompt enforcing the 3-paragraph format (<140 words).
  - Token streaming interface via Swift `AsyncStream<String>`.
  - Foreground-only execution gate (blocking execution during background sync to prevent jetsam memory eviction).

### Phase 7: Native SwiftUI Views & Interactive 60 FPS Charts
- Build SwiftUI user interface matching the architectural blueprint:
  - **Daily Readiness View:** Radial readiness score gauge, baseline delta badges, autonomic strain indicators.
  - **Sleep Architecture View:** Interactive SwiftUI Charts rendering Awake, REM, Light, and Deep stages with pinch/pan navigation at 60 FPS.
  - **AI Recovery Coach View:** Live token streaming card, historical advice browser, non-clinical wellness insights.
  - **Settings & Data Sovereignty View:** Zero-telemetry audit, BLE connection status, raw SQL export (CSV/Parquet).

### Phase 8: Background Ingestion, Reliability & App Store Hardening
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

