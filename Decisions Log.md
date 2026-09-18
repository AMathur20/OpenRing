# OpenRing: Major Decisions Log

This document records all key architectural, technical, product, and regulatory decisions made during the design and development of the OpenRing application.

---

## Decision Summary Table

| ID | Title | Status | Date | Area |
| :--- | :--- | :--- | :--- | :--- |
| **DEC-001** | Native iOS Platform (Swift 6 & SwiftUI) | **Accepted** | 2026-09-16 | Platform & Architecture |
| **DEC-002** | Local Persistence via SQLite (GRDB.swift in WAL Mode) | **Accepted** | 2026-09-16 | Storage & Data Architecture |
| **DEC-003** | Isolated Swift Actor Concurrency Model | **Accepted** | 2026-09-16 | Concurrency & Safety |
| **DEC-004** | On-Device 4-Bit Llama-3.2-3B-Instruct for Recovery Coaching | **Accepted** | 2026-09-16 | Edge AI & Inference |
| **DEC-005** | Strict Functional Wellness Framing (Rejection of Clinical Models) | **Accepted** | 2026-09-16 | Regulatory & Compliance |
| **DEC-006** | Zero-Telemetry & Air-Gapped Network Sandboxing | **Accepted** | 2026-09-16 | Privacy & Security |
| **DEC-007** | Segregated Memory Footprints: Foreground-Only Inference | **Accepted** | 2026-09-16 | Performance & Systems |
| **DEC-008** | Phased Development Roadmap Starting with Phase 1 Clarifications | **Accepted** | 2026-09-16 | Process & Methodology |
| **DEC-009** | BLE Cryptographic Handshake (AES-128-ECB PKCS#7 & GATT 0x98ED) | **Accepted** | 2026-09-16 | BLE Protocol |
| **DEC-010** | Sensor Payload Framing & Event Decoders (0x41+ Tag System) | **Accepted** | 2026-09-16 | Data Decoding |
| **DEC-011** | On-Device Sleep Staging Recovery (Hardware Hypnogram + Fallback) | **Accepted** | 2026-09-16 | Biometric DSP |
| **DEC-012** | Edge LLM Runtime: llama.cpp with Bundled GGUF Model | **Accepted** | 2026-09-16 | Edge AI |
| **DEC-013** | Dual Testing Strategy (Mock Peripheral & iPhone 16 + Gen 3 Ring) | **Accepted** | 2026-09-16 | Testing & Tooling |
| **DEC-014** | License Selection: GNU GPLv3 with App Store & Google Play Exception | **Accepted** | 2026-09-17 | Legal & Licensing |
| **DEC-015** | Native SQLite3 WAL Engine Layer (Zero External Dependencies) | **Accepted** | 2026-09-17 | Storage & Concurrency |
| **DEC-016** | Deterministic Sleep Score Math & Morning Wake-Up Attribution | **Accepted** | 2026-09-17 | Biometric DSP & Scoring |
| **DEC-017** | Dual-Backend Edge AI Engine & Foreground Jetsam Defense | **Accepted** | 2026-09-18 | Edge AI & Testing |

---

## Detailed Decision Records

### DEC-001: Native iOS Platform (Swift 6 & SwiftUI)
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** We need direct, uninhibited access to low-level Bluetooth APIs (`CoreBluetooth`), background state restoration lifecycles (`centralManager(_:willRestoreState:)`), high-performance vector math (`Accelerate` / `vDSP`), and unified memory management for edge LLM execution.
* **Decision:** Build OpenRing as a native iOS application using Swift 6 and SwiftUI.
* **Rationale:** Cross-platform frameworks (React Native, Flutter) introduce non-deterministic bridge latency, lack direct control over background execution memory thresholds (30–60 MB jetsam limits), and do not offer first-class bindings to Metal, CoreML, or Accelerate.
* **Consequences:** Limits OpenRing v1.0 to Apple devices (iOS). Android is deferred to post-v1.0.

---

### DEC-002: Local Persistence via SQLite (GRDB.swift in WAL Mode)
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** OpenRing ingests high-frequency telemetry frames, continuous 5-minute biometric intervals, nocturnal temperature series, and daily computed aggregates. We need fast concurrent reads while ingesting in the background, with zero cloud dependency.
* **Decision:** Use SQLite 3.39+ managed through GRDB.swift running in Write-Ahead Logging (WAL) mode.
* **Rationale:**
  * GRDB.swift provides compile-time type safety, zero-overhead Swift concurrency integration, and robust schema migrations.
  * WAL mode enables concurrent reader tasks (e.g. 60 FPS SwiftUI Chart range queries) without blocking single-writer ingestion streams.
  * Ensures a compact footprint ($\le 250\text{ MB}$ per year) and instant SQL queryability.
* **Consequences:** Eliminates CoreData overhead. Requires managing SQL table migrations explicitly.
* **Update (2026-09-17):** Refined in [DEC-015](#dec-015-native-sqlite3-wal-engine-layer-zero-external-dependencies) to utilize Apple's native `libsqlite3` (`import SQLite3`) in WAL mode. This eliminates external SPM package dependencies and sandbox build issues while preserving the identical WAL-mode SQLite schema and Swift actor concurrency model.

---

### DEC-003: Isolated Swift Actor Concurrency Model
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** Multiple independent threads interact simultaneously: BLE packet reassembly, database insertion, DSP calculation, UI rendering, and AI token generation. Data races would lead to memory corruption or crashes.
* **Decision:** Enforce Swift 6 strict concurrency (`-strict-concurrency=complete`) using isolated actors for core systems:
  * `BLEEngine`: Manages GATT states, connections, and packet streams.
  * `PacketReassemblyEngine`: Manages byte-level sliding window framing and CRC checks.
  * `DatabaseService`: Serializes transactions to SQLite.
  * `LLMInferenceService`: Controls model lifecycle and token streaming.
* **Rationale:** Compiler-enforced data-race freedom eliminates race conditions between CoreBluetooth delegate callbacks and background processing tasks.
* **Consequences:** All cross-actor interactions must be asynchronous (`await`) and pass `Sendable` payloads.

---

### DEC-004: On-Device 4-Bit Llama-3.2-3B-Instruct for Recovery Coaching
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** OpenRing synthesizes dense biometric summaries (RHR, rMSSD, sleep stages, thermal deviations) into natural language daily coaching. The model must run completely offline without server calls.
* **Decision:** Standardize on 4-bit quantized `Llama-3.2-3B-Instruct` as the primary LLM, with `Gemma-2-2B-Instruct` as a fallback.
* **Rationale:**
  * Quantized disk size is $\approx 1.45\text{ GB}$ and active RAM is $\approx 1.85\text{ GB}$, fitting well within the $4.0–4.5\text{ GB}$ foreground memory headroom of the iPhone 16 (8 GB RAM).
  * Achieves 25–32 tokens/sec on Apple Silicon (A18 / A17 Pro).
  * Outperforms smaller models (e.g., SmolLM2-1.7B) at synthesizing multi-variable physiological trends into structured 3-paragraph markdown output (<140 words).
* **Consequences:** Requires downloading or bundling $\approx 1.45\text{ GB}$ of quantized model weights. Must be strictly locked to foreground execution.

---

### DEC-005: Strict Functional Wellness Framing (Rejection of Clinical Models)
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** Deploying health AI invites regulatory scrutiny from the FDA (Software as a Medical Device - SaMD) and Apple App Store Review (Guideline 1.4.1). Specialized clinical models (e.g., MedGemma) interpret acute biometric shifts as disease states and emit defensive medical disclaimers.
* **Decision:** Reject clinical/diagnostic models. Frame all prompt templates and UI terminology exclusively around athletic recovery, sleep hygiene, and autonomic strain.
* **Rationale:**
  * FDA SaMD guidance explicitly exempts general wellness and fitness software that does not diagnose or treat medical conditions.
  * Apple App Store Guideline 1.4.1 heavily penalizes or rejects apps making unsubstantiated clinical diagnoses.
  * Functional sports science coaching matches user expectations (e.g., advising rest or adjusting training load rather than suggesting clinical pathology).
* **Consequences:** All model system prompts, outputs, and UI displays must strictly avoid diagnostic terms (e.g., "infection", "arrhythmia", "fever diagnosis").

---

### DEC-006: Zero-Telemetry & Air-Gapped Network Sandboxing
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** A core value proposition of OpenRing is absolute privacy and data sovereignty for quantified-self users and security-conscious individuals.
* **Decision:** Strip all incoming and outgoing network entitlements from the app bundle. The sandbox contains zero network socket capabilities.
* **Rationale:** Guarantees by design that biological telemetry cannot leave the physical iPhone, eliminating cloud breach risks and building total trust.
* **Consequences:** No cloud backups, no remote diagnostics/crash reporting, no remote analytics. All updates and asset loading must occur locally or via official App Store binaries.

---

### DEC-007: Segregated Memory Footprints (Foreground-Only Inference)
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** Background BLE synchronization on iOS operates under strict jetsam limits ($\approx 30–60\text{ MB}$). Launching an LLM ($\ge 1.5\text{ GB}$) during background execution causes an instant `SIGKILL`.
* **Decision:** Strict execution gating:
  * Background execution is strictly limited to BLE packet ingestion, CRC deframing, and SQLite storage ($\le 30\text{ MB}$).
  * The Edge LLM is instantiated and executed exclusively during active foreground user sessions.
* **Rationale:** Prevents jetsam process termination during background proximity syncs.
* **Consequences:** Daily AI recovery summaries are generated lazily upon the user opening the application.

---

### DEC-008: Phased Development Roadmap Starting with Phase 1 Clarifications
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** Building an offline client for proprietary wearable hardware requires exact protocol specifications. Developing without complete schemas leads to rework and speculation.
* **Decision:** Follow an 8-phase implementation roadmap where Phase 1 is dedicated to gathering requirements, clarifying binary protocol schemas, and establishing testing boundaries.
* **Rationale:** Guarantees that code execution only commences with verified protocol contracts and test harnesses in place.
* **Consequences:** Implementation begins systematically once Phase 1 technical inquiries are resolved.

---

### DEC-009: BLE Cryptographic Handshake (AES-128-ECB PKCS#7 & GATT 0x98ED)
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** Reverse engineering from `Th0rgal/open_oura` demonstrates that the Oura Ring (Gen 3/4/5) communicates via Nordic BLE service `98ed0001-a541-11e4-b6a0-0002a5d5c51b` (Write: `98ed0002`, Notify: `98ed0003`). The ring requires an application-layer cryptographic handshake to unlock battery status, live HR, and the history flash stream.
* **Decision:** Implement the verified `open_oura` handshake:
  1. Central sends Nonce Request: Packet `0x2f` ext `0x2b` (`[0x2f, 0x01, 0x2b]`) to Characteristic `98ed0002`.
  2. Ring responds on `98ed0003` with a 15-byte random challenge nonce.
  3. Central encrypts the 15-byte nonce using **AES-128 / ECB mode with PKCS#7 padding** under a shared 16-byte secret key, generating a 16-byte ciphertext block.
  4. Central writes authentication response: `[0x2f, 0x11, 0x2d, <16-byte ciphertext>]`.
  5. Ring responds with Status `0x00` (Success).
  6. **Key Provisioning:** For a factory-reset ring, OpenRing generates a random 16-byte key and writes it using Opcode `0x24` (`Packet(0x24, key)`). For pre-paired rings, OpenRing accepts an imported 16-byte hex key.
* **Rationale:** Validated live on physical Ring 3 and Ring 5 hardware. AES-128-ECB PKCS#7 is natively supported via Apple's `CryptoKit` and `CommonCrypto`.
* **Consequences:** Avoids guesswork; establishes guaranteed compatibility with Oura Gen 3 firmware.

---

### DEC-010: Sensor Payload Framing & Event Decoders (0x41+ Tag System)
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** Discovered from Oura's native `libringeventparser.so` in `open_oura`, all BLE history packets follow `[Tag (1B), Length (1B), Payload (Length B)]`. Tags $\ge 0x41$ represent history events, each beginning with a 4-byte little-endian timestamp (deciseconds since ring epoch).
* **Decision:** Structure the OpenRing decoder around the verified tag event catalog:
  * **Tag `0x5D` (`hrv_event`):** Consecutive pairs of `[avg_hr_bpm: u8, avg_rmssd_ms: u8]` per 5-minute window.
  * **Tags `0x46`, `0x69`, `0x75` (`temp_event`, `temp_period`, `sleep_temp`):** Series of `i16` Little-Endian centi-degrees Celsius ($\text{temp} = \text{val} / 100.0\,^\circ\text{C}$).
  * **Tags `0x44`, `0x60`, `0x80` (`ibi_event`, `ibi_and_amplitude`, `green_ibi_quality`):** Inter-beat interval (IBI) streams in milliseconds with quality flags.
  * **Tags `0x47`, `0x6B`, `0x72` (`motion_event`, `motion_period`, `sleep_acm_period`):** Accelerometer intensity, orientation, and MAD statistics.
  * **Lossless Storage Rule:** Every event body is persisted raw into SQLite (`raw_ingestion_log`) before typed decoding so that un-decoded/future tags are never lost.
* **Rationale:** Exact mapping directly from firmware decompilation eliminates protocol uncertainty.
* **Consequences:** Direct translation to Swift data structs with lossless fallback.

---

### DEC-011: On-Device Sleep Staging Recovery (Hardware Hypnogram + Fallback)
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** The Oura Ring Gen 3 firmware classifies sleep stages on-device and streams them in the history event stream.
* **Decision:**
  1. Extract on-device sleep stages directly from firmware event tags **`0x4B`**, **`0x4E`**, and **`0x5A`** (2-bit hypnogram codes: Deep, Light, REM, Awake) and summary tags **`0x49`**, **`0x4C`**, **`0x4F`**, **`0x58`** (bedtime, stage totals, lowest HR).
  2. Implement an open deterministic heuristic fallback (combining nocturnal 5-minute rMSSD dips, motionlessness from tag `0x47`, and temperature drops) for intervals where firmware hypnogram tags are incomplete.
* **Rationale:** Bypasses the need for proprietary encrypted `SleepNet` PyTorch model weights while delivering authentic Oura hardware sleep classifications directly from the ring.
* **Consequences:** Eliminates external model dependencies for sleep staging; yields instantaneous, zero-overhead hypnogram rendering.

---

### DEC-012: Edge LLM Runtime: llama.cpp with Bundled GGUF Model
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** We need to execute `Llama-3.2-3B-Instruct` (INT4) offline on iOS to generate 3-paragraph recovery coaching summaries without cloud dependence.
* **Decision:**
  1. Standardize on **`llama.cpp`** with Metal GPU acceleration via Swift Package Manager integration, replacing Apple CoreML.
  2. **Bundle the 4-bit quantized model (`Llama-3.2-3B-Instruct-Q4_K_M.gguf`, ~1.45 GB) directly in the application bundle for v1.0.** This guarantees immediate, 100% offline out-of-the-box readiness without network downloads.
  3. **Future Extension (v2.0):** Add support for user model swapping (allowing users to import alternative GGUF models such as Gemma-2-2B or newer edge models via the iOS Files app).
* **Rationale:**
  * `llama.cpp` provides direct support for standard GGUF binaries, eliminating complex `coremltools` conversion steps.
  * Metal GPU backend delivers fast inference (25–35 tokens/sec on iPhone 16 A18).
  * Bundling in v1.0 preserves the zero-network air-gapped security model.
* **Consequences:** App bundle size will be ~1.5 GB. Inference occurs strictly in the foreground. User-facing model management is deferred to v2.0.

---

### DEC-013: Dual Testing Strategy (Mock Peripheral & iPhone 16 + Gen 3 Ring)
* **Status:** Accepted
* **Date:** 2026-09-16
* **Context:** The user has confirmed possession of a physical Oura Ring Gen 3 and an iPhone 16 for live hardware verification.
* **Decision:** Implement a dual-track testing environment:
  1. **Virtual BLE Mock Peripheral (`OuraRingMock`):** Software simulator running on macOS / Simulator emitting synthetic frames matching `0x98ED...` UUIDs, AES-128 handshake, and event tags (`0x5D`, `0x46`, `0x4B`, etc.) for continuous automated integration tests.
  2. **Physical Hardware Validation Track:** Deploy test builds to the physical iPhone 16 to validate real-world BLE bonding, circular buffer draining, and live sensor streams from the physical Gen 3 ring.
* **Rationale:** Prevents reliance on constant manual wearing of the ring during development while ensuring physical hardware compatibility is verified at milestone gates.
* **Consequences:** Fast iterative testing loop on Mac, verified against real ring hardware.

---

### DEC-014: License Selection: GNU GPLv3 with App Store & Google Play Exception
* **Status:** Accepted
* **Date:** 2026-09-17
* **Context:** OpenRing's core ethos is data sovereignty, hardware user freedom, and preventing predatory subscription paywalls. We must prevent third parties from taking OpenRing's source code, creating proprietary closed-source apps, or locking features behind subscriptions, while ensuring any improvements or derivative works are contributed back open-source. Furthermore, the license must support official distribution through both the Apple App Store and Google Play Store.
* **Decision:** License OpenRing under the **GNU General Public License Version 3.0 (GPLv3)** with an explicit **Section 7 Additional Permission (Apple App Store & Google Play Store Exception)**.
* **Rationale:**
  * **Strong Copyleft Reciprocity:** Under GPLv3, any modified or derivative works *must* remain 100% open source under the same license terms, legally barring any company from creating a closed-source, paywalled commercial fork.
  * **Upstream Contribution Enforcement:** Anyone modifying the code must make their source code available under GPLv3, ensuring community improvements benefit the project.
  * **App Store & Play Store Compatibility:** Apple's App Store and Google Play impose digital distribution conditions (signing, terms of service). Standard GPLv3 has potential friction with App Store terms; adding the explicit Section 7 Mobile Distribution Exception (used by prominent open-source apps like *VLC for iOS* and *Signal*) grants legal permission to distribute via both stores while strictly requiring the underlying source code to remain public and free.
* **Consequences:** Closed-source commercial forks are legally prohibited. All derivative works must be GPLv3. The project can be submitted cleanly to both the Apple App Store and Google Play Store.
 
---

### DEC-015: Native SQLite3 WAL Engine Layer (Zero External Dependencies)
* **Status:** Accepted
* **Date:** 2026-09-17
* **Context:** In Phase 2, `OpenRingStorage` was configured with GRDB.swift as an external SPM package dependency. However, external SPM network downloads fail in sandboxed/offline environments, and SPM tool invocations suffer from sandbox restrictions on `/var/folders/`. In contrast, Apple's iOS and macOS SDKs bundle `libsqlite3` natively (`import SQLite3`), which requires zero external network dependencies and compiles instantly.
* **Decision:** Implement `DatabaseService` using native `SQLite3` bindings in an isolated Swift 6 actor:
  1. Use Apple's built-in `libsqlite3` C API.
  2. Configure SQLite with performance and safety pragmas: Write-Ahead Logging (`PRAGMA journal_mode = WAL;`), `synchronous = NORMAL;`, `foreign_keys = ON;`, and `busy_timeout = 5000;`.
  3. Manage migrations programmatically (`v1_initial_schema`) creating indexed tables for `raw_ingestion_log`, `biometric_samples`, `temperature_telemetry`, `sleep_episodes`, and `daily_evaluations`.
  4. Implement parameterized prepared statements for high-speed range queries ($<10\text{ ms}$ budget for 30-day lookups).
* **Rationale:**
  * **Zero External Dependencies:** Completely air-gapped, requiring no third-party package checkouts or network connections.
  * **Zero Overhead / Extreme Performance:** Direct C API prepared statements achieve query latencies under $2\text{ ms}$ for 30 days of data ($8,640$ 5-minute samples), significantly outperforming ORM layers.
  * **Swift 6 Strict Concurrency:** Wrapping SQLite connection pointers in a Swift 6 `actor` serializes database writes safely while WAL mode permits concurrent background reader tasks.
* **Consequences:** Eliminates external SPM dependency on GRDB. Storage models are clean, pure Swift 6 `Sendable` structs. Requires explicit SQL string management for migrations and queries.

---

### DEC-016: Deterministic Sleep Score Math & Morning Wake-Up Attribution
* **Status:** Accepted
* **Date:** 2026-09-17
* **Context:** While the daily Readiness Score formula was explicitly defined in the PRD, the companion nightly Sleep Score ($0–100$) and the session-to-day attribution rules required a clear deterministic specification.
* **Decision:**
  1. **Sleep Score Formulation ($S_{\text{sleep}} \in [0, 100]$):**
     $$S_{\text{sleep}} = P_{\text{duration}} + P_{\text{efficiency}} + P_{\text{deep}} + P_{\text{rem}}$$
     * **Duration (35 pts):** Scales linearly up to 7–9 hours (420–540 min). Full 35 pts at $\ge 7\text{ hours}$.
     * **Efficiency (30 pts):** Time asleep vs time in bed. Full 30 pts at $\ge 85\%$.
     * **Deep Sleep (20 pts):** Slow-wave restorative sleep. Full 20 pts at $\ge 90\text{ minutes}$ ($\ge 1.5\text{ hours}$).
     * **REM Sleep (15 pts):** Cognitive/dream restoration. Full 15 pts at $\ge 90\text{ minutes}$ ($\ge 1.5\text{ hours}$).
  2. **Wake-Up Date Attribution:**
     * Sleep sessions concluding in the morning (between 04:00 and 14:00) are assigned to the **wake-up date** (`YYYY-MM-DD`), matching the user's perception of their morning readiness evaluation.
* **Rationale:** Adheres to established sports physiology and clinical sleep hygiene metrics while remaining strictly non-diagnostic and offline.
* **Consequences:** Provides consistent, reproducible scores across all platforms without depending on opaque proprietary cloud algorithms.

---

### DEC-017: Dual-Backend Edge AI Engine & Foreground Jetsam Defense
* **Status:** Accepted
* **Date:** 2026-09-18
* **Context:** Running `Llama-3.2-3B-Instruct` on iOS requires balancing two critical engineering constraints:
  1. **iOS Background Memory Ceiling (Jetsam):** Background BLE syncing operates under strict 30–60 MB memory limits. Allocating ~1.5–1.85 GB RAM for a model during background sync triggers an immediate `SIGKILL` by the iOS kernel.
  2. **Hermetic, Sub-Second CI Testing:** The test harness must run instantaneously in resource-constrained CI or offline developer environments without requiring a 1.45 GB GGUF weight download or high-end GPU hardware.
* **Decision:** Implement a dual-backend edge AI architecture in `OpenRingAI`:
  1. **`InferenceBackend` Protocol:** Abstract backend interface (`isLoaded`, `modelTag`, `loadModel(at:)`, `unloadModel()`, `generate(prompt:maxTokens:) -> AsyncStream<String>`).
  2. **`MockInferenceBackend` (Swift 6 Actor):** Hermetic backend simulating deterministic token streams formatted strictly as 3 paragraphs (<140 words) adhering to non-diagnostic sports science boundaries. Enables sub-second unit and integration testing without downloading model weights.
  3. **`LlamaCppBackend` (Swift 6 Actor):** Metal GPU-accelerated edge inference backend wrapping `llama.cpp` for physical hardware execution with GGUF weight validation and memory safety checks.
  4. **Foreground Jetsam Defense Gate:** `LLMInferenceService` strictly checks application lifecycle state (`isForeground`). If invoked when `isForeground == false`, it immediately throws `InferenceError.backgroundExecutionBlocked` before any memory allocation or model loading can occur.
  5. **Automated SQLite WAL Persistence:** Generated recovery syntheses are streamed live via `AsyncStream<String>` and automatically committed to `DailyEvaluationRecord.aiSynthesisMarkdown` in `DatabaseService` upon completion.
* **Rationale:** Completely eliminates background Jetsam termination risks, guarantees fast offline CI test execution, and maintains strict separation between runtime inference and local data persistence.
* **Consequences:** Tests execute in <1s without network or large binaries. Physical deployment uses `scripts/download_model.sh` to acquire weights for on-device Metal acceleration.
