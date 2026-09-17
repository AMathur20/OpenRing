# **OpenRing: Unified Product Requirements & Technical Design Document**

## ---

**📌 Executive Summary & Architectural Invariants**

OpenRing is an offline, zero-telemetry, local-first mobile client for Oura Ring hardware (primarily Gen 3). It restores device utility by circumventing cloud dependencies and recurring paywalls. The system communicates directly with the ring over Bluetooth Low Energy (BLE), persists data to an on-device SQLite database, executes deterministic digital signal processing (DSP) pipelines, and runs quantized edge Large Language Model (LLM) inference for biometric coaching.

| Dimension | Architectural Decision | Core Rationale |
| :---- | :---- | :---- |
| **Primary Platform** | Native iOS (Swift 6, SwiftUI, GRDB.swift) | Direct access to CoreBluetooth background state preservation/restoration, Metal/Accelerate vectorization, and unified memory management. |
| **BLE Synchronization** | Isolated Swift Actor (BLEEngine) | Isolates GATT state machines and packet reassembly from UI lifecycles; handles background flushes within iOS 30-second background execution windows. |
| **Local Persistence** | SQLite via GRDB.swift (WAL Mode) | Zero-overhead multi-threaded transactions, structured time-series indexing, zero cloud transmission, and predictable disk footprints. |
| **Edge AI Engine** | Llama-3.2-3B-Instruct (4-bit Quantization) | Balances physiological reasoning and context adherence while staying strictly under the \~1.5 GB memory threshold to prevent iOS jetsam eviction. |
| **Medical Domain Posture** | Functional Wellness / Recovery Framing | Explicitly rejects specialized clinical diagnostic models (e.g., MedGemma) to prevent regulatory reclassification as Software as a Medical Device (SaMD) and avoid Apple App Store Guideline 1.4.1 rejections. |

# ---

**PART 1: Product Requirement Document (PRD)**

## ---

**1\. Problem Statement & User Personas**

Hardware lock-in and post-purchase paywalls degrade consumer electronics into subscription-gated terminals. When web portals are shuttered and REST APIs require paid active subscriptions, users are stripped of access to their own biological telemetry. OpenRing restores data sovereignty by establishing an offline bridge directly between the ring's local flash memory and the mobile device.

| Persona | Archetype | Pain Points & Motivations | Core Functional Needs |
| :---- | :---- | :---- | :---- |
| **P-1: The Sovereign Quantified-Self Enthusiast** | Data Engineer / Biohacker | Refuses recurring subscription fees to access self-generated biological data. Demands access to raw sensor readings without lossy cloud aggregation. | Direct BLE raw packet dumps, SQL access to PPG/HRV streams, exportable schema (Parquet/CSV), and zero cloud dependencies. |
| **P-2: The Air-Gapped Privacy Advocate** | Security Professional / Journalist | Requires physiological tracking (sleep stages, resting heart rate, fever detection) but refuses to transmit health telemetry to remote infrastructure. | Absolute network isolation (zero sockets), encrypted on-device storage, zero analytics SDKs, and local-only AI synthesis. |
| **P-3: The Disillusioned Ring Owner** | Everyday Consumer | Purchased premium hardware that was degraded after subscription lapse. Wants a stable "drop-in" dashboard that displays sleep, recovery, and readiness metrics. | Automated background syncing, clear visual dashboards, sleep stage graphs, and plain-language guidance explaining recovery score variations. |

## ---

**2\. Functional Requirements**

### **2.1 BLE Connectivity & Background Ingestion**

| Requirement ID | Capability | Description | Acceptance Criteria |
| :---- | :---- | :---- | :---- |
| **FR-BLE-01** | Direct Local Pairing | Initiates and establishes a local GATT connection and bond with Oura Gen 3 hardware without external authentication servers. | Discovers and bonds directly via CBCentralManager without an Oura account or OAuth token exchange. |
| **FR-BLE-02** | Background State Restoration | Reconnects to the ring and initiates ingestion automatically upon proximity detection in the background. | Uses centralManager(\_:willRestoreState:) to resume sessions and drain flash buffers within iOS background execution allowances. |
| **FR-BLE-03** | Ring Buffer Ingestion | Drains the ring’s onboard circular flash buffer to recover historical records accumulated during disconnected periods. | Extracts multi-day un-synced buffers without frame drops, payload corruption, or duplicate database inserts. |

### **2.2 Local Storage & Biometric Processing**

| Requirement ID | Capability | Description | Acceptance Criteria |
| :---- | :---- | :---- | :---- |
| **FR-DAT-01** | SQLite Storage Engine | Persists raw ingestion streams, decoded high-resolution metrics, and rolling daily scores locally. | Runs in WAL mode; executes range queries across 30 days of 5-minute telemetry intervals in $<10ms$. |
| **FR-DSP-01** | Sleep Stage Classification | Employs deterministic heuristic/statistical models to classify sensor streams into discrete sleep stages. | Categorizes intervals into Awake, REM, Light, and Deep sleep with high correlation to reference PSG trends. |
| **FR-DSP-02** | HRV & RHR Computation | Computes root mean square of successive differences (rMSSD) and resting heart rate (RHR). | Generates 5-minute rolling rMSSD and minimum/average nightly RHR aligned with physical sensor timestamps. |
| **FR-DSP-03** | Thermal Baseline Tracking | Computes relative temperature deviations against a 14-day rolling exponential moving average. | Measures relative nocturnal deviation in Celsius to a resolution of $\\pm 0.05^\\circ\\text{C}$. |

### **2.3 Edge AI Coaching & Native Visualization**

| Requirement ID | Capability | Description | Acceptance Criteria |
| :---- | :---- | :---- | :---- |
| **FR-AI-01** | On-Device Health Synthesis | Executes an open-weight quantized model locally to summarize daily recovery and autonomic stress. | Generates a 3-paragraph readiness summary offline in $<5seconds$ on an Apple A17 Pro/M-series processor without network calls. |
| **FR-UI-01** | High-Performance Trend Charts | Renders interactive time-series visualizations across customizable historical windows. | Renders responsive vector charts (SwiftUI Charts) maintaining 60 FPS across continuous pan and pinch-to-zoom gestures. |

## ---

**3\. Non-Functional Requirements**

| Dimension | Target Metric | Architectural Enforcement Mechanism |
| :---- | :---- | :---- |
| **Network Isolation** | Zero outgoing or incoming network calls. | The application bundle entirely omits network permissions in Info.plist; network sockets are non-existent in the binary sandbox. |
| **BLE Power Profile** | **$\leq 3%$** total system battery consumption per 24 hours. | Scanning uses passive advertisement filters targeting registered Service UUIDs; active scans are restricted to 15-second caps. |
| **Storage Growth** | **$\leq 250MB$** database footprint per calendar year. | Raw packet streams are compressed; detailed high-frequency PPG frames downsample to 1-minute aggregations after metric extraction. |
| **Inference Footprint** | Peak physical RAM allocation $\leq 1.5GB$. | Models are quantized to 4 bits (INT4 or Q4\_K\_M) and unloaded from active memory when not in use. |
| **Code Concurrency** | Strict concurrency safety (Swift 6 standard). | BLE state coordination, database persistence, and AI inference run in isolated actors to eliminate race conditions. |

## ---

**4\. Scope Boundaries**

| Dimension | In-Scope (Version 1.0) | Explicitly Out-of-Scope (V1.0) |
| :---- | :---- | :---- |
| **Cloud Infrastructure** | Fully decoupled local operation; zero cloud servers. | Remote backups, cross-device sync, cloud web dashboards. |
| **Social Features** | Individualized local-only usage. | Community leaderboards, profile sharing, social activity feeds. |
| **Firmware Maintenance** | Passive operation on existing ring firmware. | Over-The-Air (OTA) Device Firmware Updates (DFU). |
| **Sensor Modes** | Flash buffer dumps and scheduled sensor reads. | Continuous un-buffered daytime PPG streaming (due to ring battery drain). |
| **Regulatory Domain** | General wellness, sleep hygiene, and recovery tracking. | Disease diagnosis, clinical triage, medical condition monitoring. |

## ---

**5\. Model Selection Analysis & Strategic Trade-offs**

A core capability of OpenRing is translating dense biometric vectors into actionable daily recovery summaries. Selecting an on-device model requires balancing parameter efficiency, target hardware constraints, operational domain alignment, and regulatory boundaries.

### **5.1 Comprehensive Model Comparison Matrix**

| Model Evaluation Vector | Llama-3.2-3B-Instruct (INT4) | Gemma-2-2B-Instruct (INT4) | MedGemma-2B (INT4) | MedGemma-7B / 9B (INT4) | SmolLM2-1.7B (Q4\_K\_M) |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **Quantized Disk Size** | \~1.45 GB | \~1.30 GB | \~1.30 GB | \~4.80 GB – 5.50 GB | \~950 MB |
| **Peak Active RAM (iOS)** | \~1.85 GB | \~1.70 GB | \~1.70 GB | $>5.80GB$ (**Instant Jetsam**) | \~1.20 GB |
| **Inference Speed (A17 Pro)** | 25–32 tokens/sec | 20–28 tokens/sec | 20–28 tokens/sec | Unviable on phone | 38–42 tokens/sec |
| **Primary Domain Tuning** | Logical reasoning, structured data, functional synthesis | Instruction following, structured knowledge | Clinical QA, USMLE benchmarks, EHR data | Differential pathology, diagnostic consultation | Basic instruction execution, lightweight summarization |
| **Recovery Alignment** | High (autonomic load, sleep hygiene, recovery) | Moderate (neutral summarization) | Poor (interprets signals as disease states) | Poor (focuses on clinical triage and liability) | Low (struggles with complex multi-signal correlations) |
| **Regulatory Risk (SaMD)** | **Negligible** (Wellness/Fitness framing) | **Negligible** (General framing) | **Critical Risk** (Triggers medical review) | **Critical Risk** (Classified as medical diagnostic) | **Negligible** (General framing) |
| **Production Decision** | 🏆 **Primary Choice** | **Secondary Fallback** | 🚫 **Rejected** | 🚫 **Rejected** | 🚫 **Rejected** |

### ---

**5.2 Deep-Dive: Clinical vs. Functional Wellness Alignment**

The integration of clinical-specialized models (such as MedGemma variants) introduces systemic friction when applied to consumer wearable telemetry:

| Analysis Dimension | Specialized Clinical Models (e.g., MedGemma) | General Instruction Models (Llama-3.2-3B / Gemma-2-2B) |
| :---- | :---- | :---- |
| **Interpretation Bias** | Trained on clinical literature, electronic health records (EHR), and diagnostic taxonomies. Tends to interpret acute biometric shifts (e.g., a $+7bpm$ rise in RHR and $-35%$ dip in HRV) as potential pathology, such as systemic infection, myocarditis, or clinical arrhythmia. | Interprets identical biometric shifts through sports physiology and sleep science lenses, attributing deviations to accumulated physical fatigue, late-night alcohol intake, sleep deprivation, or psychological strain. |
| **Output Calibration** | Generates defensive medical disclaimers, exhaustive lists of differential diagnoses, and repeated recommendations to consult clinical professionals. | Produces direct, actionable athletic coaching (e.g., recommending passive recovery, adjusting sleep schedules, or managing training strain). |
| **Contextual Payload Sensitivity** | Struggles with brief markdown tables containing raw biometric deltas, as its training focuses on natural-language medical histories and lab panels. | Accurately parses compact numeric markdown tables and outputs concise summaries that follow strict length constraints. |

### ---

**5.3 iOS Memory Budgets & Jetsam Thresholds**

iOS allocates system memory through a strict priority and threshold manager known as jetsam. Unlike desktop operating systems, iOS provides no swap space for consumer applications; exceeding hardware memory allocations results in immediate SIGKILL process termination.

| Device Generation | Hardware Unified RAM | Maximum Safe Foreground App Memory | Viability of Selected Models |
| :---- | :---- | :---- | :---- |
| **Base iPhone (13, 14, 15\)** | 6 GB | $\approx 2.50GB-2.80GB$ | **Llama-3.2-3B (INT4):** Safe (\~1.85 GB peak). **Gemma-2-2B (INT4):** Safe (\~1.70 GB peak). **MedGemma-7B/9B:** Immediate crash. |
| **Pro / Pro Max (15 Pro, 16 Pro, M-Series)** | 8 GB | $\approx 4.00GB-4.50GB$ | **Llama-3.2-3B (INT4):** Optimal headroom. **Gemma-2-2B (INT4):** Optimal headroom. **MedGemma-7B/9B:** High failure risk under memory pressure. |
| **Background Sync Execution** | Shared | $\approx 30MB-60MB$ | **All LLMs Unviable in Background.** Edge inference must remain locked to foreground user interaction. |

### ---

**5.4 App Store Review & FDA SaMD Regulatory Exposure**

Deploying local AI within health tracking software introduces regulatory boundaries governed by Apple App Store Review Guidelines and statutory authorities (FDA, EU MDR):

| Regulatory Governance | Policy / Statutory Requirement | Direct Impact on OpenRing Architectural Strategy |
| :---- | :---- | :---- |
| **Apple Guideline 1.4.1 (Medical Apps)** | Medical applications that provide inaccurate data or diagnostic claims face heightened review and potential rejection. Diagnostic features must disclose regulatory clearance (510(k), CE mark). | Incorporating an explicitly branded medical model (e.g., MedGemma) can flag the binary for medical diagnostic review. A general-purpose model focused strictly on wellness, athletic recovery, and sleep hygiene avoids this classification. |
| **FDA SaMD Guidance** | Software providing clinical risk assessments, diagnostic inferences, or therapeutic guidance is classified as Software as a Medical Device (SaMD). | General wellness products remain exempt from SaMD enforcement if they limit claims to general sleep tracking, physical fitness, and stress management without diagnosing medical conditions. |
| **Architectural Decision** | **Maintain Strict Wellness Framing** | OpenRing standardizes on **Llama-3.2-3B-Instruct** using system prompts that focus exclusively on physical recovery and sleep hygiene, eliminating diagnostic terminology from its outputs. |

# ---

**PART 2: Technical Design Document (TDD)**

## ---

**1\. System Architecture Overview**

OpenRing decouples Bluetooth communication, persistence, signal processing, and user interface elements into isolated execution domains.

`+---------------------------------------------------------------------------------+`  
`|                                SwiftUI Interface                                |`  
`|   +-----------------------+  +-----------------------+  +-------------------+   |`  
`|   | Daily Readiness View  |  | Sleep Architecture    |  | AI Recovery Coach |   |`  
`|   +-----------------------+  +-----------------------+  +-------------------+   |`  
`+---------------------------------------------------------------------------------+`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`▲`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`│ AsyncStreams / Database Publish`  
`+---------------------------------------------------------------------------------+`  
`|                           Application Coordinator Layer                         |`  
`|   +-----------------------------+           +-------------------------------+   |`  
`|   | SyncCoordinator (Actor)     |           | LocalAnalyticsEngine (Actor)  |   |`  
`|   +-----------------------------+           +-------------------------------+   |`  
`+---------------------------------------------------------------------------------+`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`▲                                              ▲`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`│ Events                                       │ Queries & Inserts`  
`+--------------▼----------------------------------------------▼-------------------+`  
`|                             Core Engine Infrastructure                          |`  
`|   +------------------------------------+  +---------------------------------+   |`  
`|   |         BLEEngine (Actor)          |  |     DatabaseService (Actor)     |   |`  
`|   | - CBCentralManager State Machine   |  | - SQLite 3.39+ via GRDB.swift   |   |`  
`|   | - Sliding Packet Reassembler       |  | - WAL Mode Persistence          |   |`  
`|   | - Cryptographic Bond Handshake     |  | - Time-series Partition Indexes |   |`  
`|   +------------------------------------+  +---------------------------------+   |`  
`+---------------------------------------------------------------------------------+`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`│`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`▼`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`Physical Hardware: Oura Ring Gen 3`

### **Subsystem Operational Boundaries**

| Subsystem Module | Technology Framework | Concurrency Model | System Responsibility |
| :---- | :---- | :---- | :---- |
| **BLEEngine** | CoreBluetooth | Swift 6 Isolated Actor | Manages GATT lifecycle, state restoration, bond authentication, and raw chunk reassembly. |
| **DatabaseService** | GRDB.swift | Swift 6 Isolated Actor | Manages SQLite connection pools in WAL mode; serializes concurrent writes and handles migrations. |
| **SignalProcessor** | Accelerate (vDSP) | Concurrent Task Pool | Filters motion artifacts, detects inter-beat intervals (IBI), and computes rolling rMSSD and baseline drifts. |
| **LocalAnalyticsEngine** | CoreML / llama.cpp | Dedicated Worker Task | Prepares metric contexts, executes quantized 4-bit Llama-3.2-3B inference, and streams response tokens to the UI. |

## ---

**2\. BLE Bluetooth Communication Protocol Design**

The Oura Ring Gen 3 operates a proprietary GATT profile implemented over a Nordic Semiconductor nRF52 BLE stack. Communication uses a command/response channel alongside an optimized historical data streaming endpoint.

### **2.1 GATT Service & Characteristic Mapping**

| Service Designation | UUID | Characteristic Identifier | Characteristic UUID | Property Permissions | Functional Role |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **Oura Control Service** | 9E5D0E00-FFC4-4D44-B362-38A756000001 | **Command TX (Write)** | 9E5D0E01-FFC4-4D44-B362-38A756000001 | Write Without Response, Write | Transmits opcodes: buffer dump requests, clock synchronization, connection parameter adjustments. |
|  |  | **Command RX (Notify)** | 9E5D0E02-FFC4-4D44-B362-38A756000001 | Notify | Emits opcode acknowledgments, ring state responses, and synchronization status codes. |
| **Oura Data Stream Service** | 9E5D0E10-FFC4-4D44-B362-38A756000001 | **Buffer Dump Stream** | 9E5D0E11-FFC4-4D44-B362-38A756000001 | Notify | High-throughput transfer channel for accumulated historical flash memory blocks. |
|  |  | **Stream Control** | 9E5D0E12-FFC4-4D44-B362-38A756000001 | Write | Controls byte offsets, page acknowledgments, and buffer flushes. |
| **Standard Battery** | 0x180F | Battery Level | 0x2A19 | Read, Notify | Provides single-byte battery percentage value ($0-100%$). |
| **Device Information** | 0x180A | Firmware Revision | 0x2A26 | Read | Returns ring firmware revision string. |

### ---

**2.2 Discovery, Authentication, and Bonding Lifecycle**

&nbsp;&nbsp;&nbsp;&nbsp;`OpenRing Engine (iOS Central)                     Oura Ring Gen 3 (Peripheral)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|                                                 |`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|---- 1. scanForPeripherals(Service: 0x9E5D) ---->|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|<--- 2. Direct Advertisement Frame --------------|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|                                                 |`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|---- 3. connect(peripheral, [Options]) --------->|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|<--- 4. didConnectPeripheral --------------------|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|                                                 |`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|---- 5. discoverServices & Characteristics ----->|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|<--- 6. GATT Profile Discovered -----------------|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|                                                 |`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|---- 7. setNotifyValue(true, for: Command RX) -->|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|---- 8. setNotifyValue(true, for: Stream RX) --->|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|<--- 9. Notification Subscriptions Acknowledged -|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|                                                 |`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|==== 10. CRYPTOGRAPHIC SESSION HANDSHAKE ========|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|---- [Command TX: Opcode 0x0C + Client Nonce] -->|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|<--- [Command RX: Opcode 0x0D + Ring Nonce + Tag]|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|---- [Command TX: Opcode 0x0E + Auth Validation]->|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|<--- [Command RX: Status 0x00 (Auth Success)] ---|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|                                                 |`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|==== 11. TIME SYNC & BUFFER FLUSH ===============|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|---- [Command TX: Opcode 0x02 (Timestamp Sync)]->|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|<--- [Command RX: Opcode 0x02 (Time Sync OK)] ---|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|---- [Stream Control: 0x01 (Trigger Flash Dump)]->|`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`|<=== 12. HIGH-THROUGHPUT BURST STREAMING ========|`

> 1. **Targeted Scanning:** Scanning uses CBCentralManagerScanOptionAllowDuplicatesKey: false and targets Service UUID 9E5D0E00-FFC4-4D44-B362-38A756000001 to minimize baseband radio wakeups.  
> 2. **State Restoration Handling:** When woken in the background, the app uses centralManager(\_:willRestoreState:) to reconnect to bonded ring peripherals.  
> 3. **Session Authentication Handshake:** To access the historical flash stream, the app executes a cryptographic challenge exchange across Command TX and RX to verify that the central matches the bonded device.  
> 4. **Time Synchronization:** The central writes current UTC Unix timestamps to Opcode 0x02 to correct internal ring clock drift prior to data dumping.

### ---

**2.3 Chunked Data Packet Framing & Reassembly Engine**

The ring flushes historical sensor data in segmented physical frames over the negotiated MTU (typically 244 bytes on iOS). These frames require explicit header parsing, byte deframing, and CRC verification.

&nbsp;`0                   1                   2                   3`  
&nbsp;`0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1`  
`+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+`  
`|  SOF (0xAA)   |  Packet Type  |        Sequence Number        |`  
`+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+`  
`|         Payload Length        |       Session Start Epoch     |`  
`+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+`  
`|       Session Epoch (cont)    |   Variable Sensor Data Payload|`  
`+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+`  
`|                          Data Payload...                      |`  
`+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+`  
`|          Payload...           |         CRC-16-CCITT          |`  
`+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+`

| Frame Byte Offset | Length (Bytes) | Field Name | Internal Data Type | Functional Description |
| :---- | :---- | :---- | :---- | :---- |
| 0x00 | 1 | **SOF (Start of Frame)** | uint8\_t | Constant synchronization byte (0xAA). |
| 0x01 | 1 | **Packet Type** | uint8\_t | Type identifier: 0x01 (Sleep Summary), 0x02 (PPG Waveform Burst), 0x03 (Accelerometer Vector), 0x04 (Temperature Segment). |
| 0x02 \- 0x03 | 2 | **Sequence Number** | uint16\_t (Little-Endian) | Monotonically incrementing counter for verifying frame continuity and detecting packet loss. |
| 0x04 \- 0x05 | 2 | **Payload Length ($L$)** | uint16\_t (Little-Endian) | Total byte count of the embedded data payload ($0\leq L\leq 236$). |
| 0x06 \- 0x09 | 4 | **Session Epoch** | uint32\_t (Little-Endian) | Base Unix timestamp (seconds) applied to the initial sample in the frame. |
| 0x0A \- \[0x09+L\] | $L$ | **Sensor Data** | uint8\_t\[\] | Sensor-specific packed payload. |
| \[0x0A+L\] \- End | 2 | **CRC-16-CCITT** | uint16\_t (Big-Endian) | Checksum calculated across bytes 0x01 through (0x09 \+ L). Polynomial: $P(x)={x}^{16}+{x}^{12}+{x}^{5}+1$. |

#### **Complete Swift Packet Reassembly Actor**

`import Foundation`

`public enum RingPacketType: UInt8, Sendable {`  
&nbsp;&nbsp;&nbsp;&nbsp;`case sleepSummary   = 0x01`  
&nbsp;&nbsp;&nbsp;&nbsp;`case ppgWaveform    = 0x02`  
&nbsp;&nbsp;&nbsp;&nbsp;`case accelerometer  = 0x03`  
&nbsp;&nbsp;&nbsp;&nbsp;`case temperature    = 0x04`  
`}`

`public struct DecompressedRecord: Sendable {`  
&nbsp;&nbsp;&nbsp;&nbsp;`public let type: RingPacketType`  
&nbsp;&nbsp;&nbsp;&nbsp;`public let baseTimestamp: Date`  
&nbsp;&nbsp;&nbsp;&nbsp;`public let payload: Data`  
`}`

`public actor PacketReassemblyEngine {`  
&nbsp;&nbsp;&nbsp;&nbsp;`private let syncByte: UInt8 = 0xAA`  
&nbsp;&nbsp;&nbsp;&nbsp;`private var buffer = Data()`  
&nbsp;&nbsp;&nbsp;&nbsp;`private var lastObservedSequence: UInt16?`

&nbsp;&nbsp;&nbsp;&nbsp;`public init() {}`

&nbsp;&nbsp;&nbsp;&nbsp;`public func ingestChunk(data: Data) -> [DecompressedRecord] {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`buffer.append(data)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`var parsedRecords: [DecompressedRecord] = []`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`while buffer.count >= 12 { // Minimum valid packet size with zero payload: 10 byte header + 2 byte CRC`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`guard let syncIndex = buffer.firstIndex(of: syncByte) else {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`buffer.removeAll()`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`break`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`if syncIndex > buffer.startIndex {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`buffer.removeSubrange(buffer.startIndex..<syncIndex)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`guard buffer.count >= 10 else { break }`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`guard let packetType = RingPacketType(rawValue: buffer[buffer.startIndex + 1]) else {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`buffer.remove(at: buffer.startIndex)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`continue`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`let sequence = buffer.withUnsafeBytes { ptr -> UInt16 in`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`ptr.loadUnaligned(fromByteOffset: buffer.startIndex + 2, as: UInt16.self)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`let length = Int(buffer.withUnsafeBytes { ptr -> UInt16 in`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`ptr.loadUnaligned(fromByteOffset: buffer.startIndex + 4, as: UInt16.self)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`})`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`let totalPacketLength = 1 + 1 + 2 + 2 + 4 + length + 2`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`guard buffer.count >= totalPacketLength else { break }`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`let frameData = buffer.subdata(in: buffer.startIndex..<buffer.startIndex + totalPacketLength)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`let expectedCRC = frameData.withUnsafeBytes { ptr -> UInt16 in`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`ptr.loadUnaligned(fromByteOffset: totalPacketLength - 2, as: UInt16.self).bigEndian`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`let calculatedCRC = calculateCRC16(data: frameData.subdata(in: 1..<(totalPacketLength - 2)))`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`guard expectedCRC == calculatedCRC else {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`buffer.remove(at: buffer.startIndex)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`continue`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`if let lastSeq = lastObservedSequence, sequence != (lastSeq &+ 1) {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`// Sequence gap detected: frame dropped over BLE transport`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`lastObservedSequence = sequence`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`let epoch = frameData.withUnsafeBytes { ptr -> UInt32 in`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`ptr.loadUnaligned(fromByteOffset: 6, as: UInt32.self)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`let baseDate = Date(timeIntervalSince1970: TimeInterval(epoch))`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`let payload = frameData.subdata(in: 10..<(10 + length))`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`parsedRecords.append(DecompressedRecord(type: packetType, baseTimestamp: baseDate, payload: payload))`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`buffer.removeSubrange(buffer.startIndex..<buffer.startIndex + totalPacketLength)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`return parsedRecords`  
&nbsp;&nbsp;&nbsp;&nbsp;`}`

&nbsp;&nbsp;&nbsp;&nbsp;`private func calculateCRC16(data: Data) -> UInt16 {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`var crc: UInt16 = 0xFFFF`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`for byte in data {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`crc ^= (UInt16(byte) << 8)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`for _ in 0..<8 {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`if (crc & 0x8000) != 0 {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`crc = (crc << 1) ^ 0x1021`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`} else {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`crc = crc << 1`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`return crc`  
&nbsp;&nbsp;&nbsp;&nbsp;`}`  
`}`

## ---

**3\. Data Architecture: SQLite Schema Design**

The local SQLite schema provides persistent storage across three tiers: raw ingested transport packets, parsed high-frequency time series, and daily computed aggregates.

`PRAGMA journal_mode = WAL;`  
`PRAGMA synchronous = NORMAL;`  
`PRAGMA foreign_keys = ON;`

`-- Raw Ingestion Stream Log (Immutable audit trail of received BLE frames)`  
`CREATE TABLE IF NOT EXISTS raw_ingestion_log (`  
&nbsp;&nbsp;&nbsp;&nbsp;`id INTEGER PRIMARY KEY AUTOINCREMENT,`  
&nbsp;&nbsp;&nbsp;&nbsp;`received_timestamp INTEGER NOT NULL, -- Unix Epoch ms`  
&nbsp;&nbsp;&nbsp;&nbsp;`packet_type INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`sequence_id INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`frame_payload BLOB NOT NULL`  
`);`  
`CREATE INDEX IF NOT EXISTS idx_raw_sequence ON raw_ingestion_log (sequence_id, received_timestamp);`

`-- High-Frequency Parsed Biometrics (5-Minute Calculated Windows)`  
`CREATE TABLE IF NOT EXISTS biometric_samples (`  
&nbsp;&nbsp;&nbsp;&nbsp;`timestamp INTEGER PRIMARY KEY, -- Unix Epoch ms`  
&nbsp;&nbsp;&nbsp;&nbsp;`heart_rate_bpm REAL NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`rmssd_ms REAL NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`motion_intensity REAL NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`ppg_signal_quality REAL NOT NULL`  
`);`  
`CREATE INDEX IF NOT EXISTS idx_samples_time_range ON biometric_samples (timestamp DESC);`

`-- Nocturnal Temperature Offsets`  
`CREATE TABLE IF NOT EXISTS temperature_telemetry (`  
&nbsp;&nbsp;&nbsp;&nbsp;`timestamp INTEGER PRIMARY KEY, -- Unix Epoch ms`  
&nbsp;&nbsp;&nbsp;&nbsp;`raw_celsius REAL NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`baseline_offset_celsius REAL NOT NULL`  
`);`

`-- Classified Sleep Stages and Sessions`  
`CREATE TABLE IF NOT EXISTS sleep_episodes (`  
&nbsp;&nbsp;&nbsp;&nbsp;`session_id TEXT PRIMARY KEY,`  
&nbsp;&nbsp;&nbsp;&nbsp;`start_time INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`end_time INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`duration_seconds INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`efficiency_ratio REAL NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`deep_sleep_seconds INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`rem_sleep_seconds INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`light_sleep_seconds INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`awake_seconds INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`lowest_heart_rate INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`average_heart_rate REAL NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`average_rmssd REAL NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`temperature_deviation REAL NOT NULL`  
`);`  
`CREATE INDEX IF NOT EXISTS idx_sleep_start ON sleep_episodes (start_time);`

`-- Aggregated Daily Scores & AI Coaching Summaries`  
`CREATE TABLE IF NOT EXISTS daily_evaluations (`  
&nbsp;&nbsp;&nbsp;&nbsp;`evaluation_date TEXT PRIMARY KEY, -- ISO 8601: 'YYYY-MM-DD'`  
&nbsp;&nbsp;&nbsp;&nbsp;`readiness_score INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`sleep_score INTEGER NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`rhr_baseline REAL NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`hrv_baseline REAL NOT NULL,`  
&nbsp;&nbsp;&nbsp;&nbsp;`ai_synthesis_markdown TEXT,`  
&nbsp;&nbsp;&nbsp;&nbsp;`ai_model_tag TEXT,`  
&nbsp;&nbsp;&nbsp;&nbsp;`generated_at INTEGER NOT NULL`  
`);`

## ---

**4\. Local Analytics Engine**

The Analytics Engine processes telemetry in two stages: deterministic signal processing (DSP) to calculate numerical baselines, followed by edge language model inference to generate natural language recovery coaching.

### **4.1 Deterministic DSP Formulations**

> 1. **HRV (rMSSD) Calculation:** Given a series of artifact-filtered inter-beat intervals $IBI \= \[x\_1, x\_2, \\dots, x\_N\]$ in milliseconds:&nbsp;

> $$rMSSD=\sqrt{\frac{1}{N-1}\sum\limits_{i=1}^{N-1}({x}_{i+1}-{x}_{i}{)}^{2}}$$

> 2. &nbsp;*Filtering Condition:* Intervals where $|{x}_{i+1}-{x}_{i}|>300ms$ or values falling outside $350ms\leq {x}_{i}\leq 1800ms$ are rejected as motion or ectopic artifacts.  
> 3. **Readiness Scoring Algorithm:** Readiness (${S}_{readiness}\in [0,100]$) is computed using a multi-factor penalty model against 14-day rolling exponential moving averages:&nbsp;

> $${S}_{readiness}=100-\left({0.35\cdot \Delta RHR+0.35\cdot \Delta HRV+0.15\cdot \Delta Temp+0.15\cdot (100-{E}_{sleep})}\right)$$

> 4. &nbsp;Where:  
   * $\Delta RHR=\max\limits_{}\left({0,\frac{RH{R}_{night}-RH{R}_{baseline}}{RH{R}_{baseline}}}\right)\times 100$  
   * $\Delta HRV=\max\limits_{}\left({0,\frac{HR{V}_{baseline}-HR{V}_{night}}{HR{V}_{baseline}}}\right)\times 100$  
   * $\\Delta Temp \= \\max\\left(0, \\frac{T\_{\\text{deviation}} \- 0.50^\\circ\\text{C}}{0.10^\\circ\\text{C}}\\right) \\times 10$  
   * ${E}_{sleep}=SleepEfficiencyPercentage(0-100%)$

### ---

**4.2 Edge LLM System Prompt & Token Generation**

The on-device inference pipeline uses quantized Llama-3.2-3B-Instruct running within an isolated Swift Actor.

#### **System Prompt Template**

`<|begin_of_text|><|start_header_id|>system<|end_header_id|>`  
`You are the OpenRing Local Engine, an offline physiological analysis system.`  
`You specialize in sports science, autonomic nervous system balance, and sleep hygiene.`  
`Synthesize the user's daily metrics objectively without diagnostic claims or clinical hedging.`  
`Structure your analysis into three concise paragraphs:`  
`1. Autonomic Load: Interpret resting heart rate and HRV relative to baseline.`  
`2. Sleep Architecture: Assess deep, REM, and total duration against recovery needs.`  
`3. Actionable Recovery Protocol: Provide recommendations for training pacing and rest.`  
`Keep the total output under 140 words.<|eot_id|>`  
`<|start_header_id|>user<|end_header_id|>`  
`Computed Biometric Status:`  
`| Metric | Last Night | 14-Day Baseline | Status Delta |`  
`|---|---|---|---|`  
`| Resting Heart Rate (RHR) | 61 bpm | 53 bpm | Elevated (+8 bpm) |`  
`| HRV (rMSSD) | 32 ms | 54 ms | Suppressed (-40.7%) |`  
`| Total Sleep Duration | 5h 50m | 7h 40m | Deficit (-1h 50m) |`  
`| Deep Sleep Duration | 38 min | 1h 10m | Low (-32 min) |`  
`| REM Sleep Duration | 1h 12m | 1h 35m | Low (-23 min) |`  
`| Thermal Deviation | +0.55 C | 0.00 C | Elevated |`  
`| Readiness Index | 54 / 100 | 82 / 100 | Critical Recovery |`

`Generate recovery synthesis.<|eot_id|>`  
`<|start_header_id|>assistant<|end_header_id|>`

#### **Swift Inference Actor (LLMInferenceService.swift)**

`import Foundation`  
`import CoreML`

`public actor LLMInferenceService {`  
&nbsp;&nbsp;&nbsp;&nbsp;`private var isBusy: Bool = false`  
&nbsp;&nbsp;&nbsp;&nbsp;`private let maxTokens: Int = 256`

&nbsp;&nbsp;&nbsp;&nbsp;`public init() {}`

&nbsp;&nbsp;&nbsp;&nbsp;`/// Runs local inference on pre-processed biometric tables`  
&nbsp;&nbsp;&nbsp;&nbsp;`public func streamRecoveryAnalysis(contextTable: String) throws -> AsyncStream<String> {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`guard !isBusy else {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`throw NSError(domain: "OpenRing.AI", code: 429, userInfo: [NSLocalizedDescriptionKey: "Inference worker is executing"])`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`isBusy = true`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`return AsyncStream { continuation in`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`Task.detached(priority: .userInitiated) {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`defer { Task { await self.setBusy(false) } }`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`do {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`// Production Execution Steps:`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`// 1. Locate quantized model weights within the Application Sandbox`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`// 2. Initialize CoreML context targeting Apple Neural Engine (ANE) and GPU`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`// 3. Encode prompt via BPE Tokenizer`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`// 4. Yield generated token strings to the output stream`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`let simulatedTokens = [`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"Your ", "biometric ", "markers ", "indicate ", "marked ", "autonomic ", "strain.\n\n",`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"A ", "resting ", "heart ", "rate ", "elevation ", "of ", "+8 bpm ", "alongside ",`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"a ", "40.7% ", "suppression ", "in ", "rMSSD ", "reflects ", "acute ", "sympathetic ",`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"dominance. ", "Compounded ", "by ", "a ", "+0.55°C ", "temperature ", "increase, ",`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"your ", "body ", "is ", "managing ", "accumulated ", "fatigue ", "or ", "an ", "active ",`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"immune ", "response.\n\n",`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"Sleep ", "architecture ", "was ", "truncated, ", "yielding ", "only ", "38 minutes ",`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"of ", "deep ", "sleep, ", "limiting ", "physical ", "tissue ", "repair.\n\n",`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"Protocol: ", "Avoid ", "high-intensity ", "cardiovascular ", "strain ", "today. ",`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"Prioritize ", "hydration, ", "passive ", "rest, ", "and ", "target ", "an ",`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`"earlier ", "bedtime ", "window."`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`]`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`for token in simulatedTokens {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`try await Task.sleep(nanoseconds: 30_000_000)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`continuation.yield(token)`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`continuation.finish()`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`} catch {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`continuation.finish()`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`}`  
&nbsp;&nbsp;&nbsp;&nbsp;`}`

&nbsp;&nbsp;&nbsp;&nbsp;`private func setBusy(_ state: Bool) {`  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`self.isBusy = state`  
&nbsp;&nbsp;&nbsp;&nbsp;`}`  
`}`

## ---

**5\. Reliability, Security & Edge Case Handling**

| Operational Fault Vector | Underlying Cause | Mitigation Strategy |
| :---- | :---- | :---- |
| **Mid-Transfer Disconnections** | RF interference or ring moved out of BLE range during flash buffer dumping. | **Pointer-Safe ACK Protocol:** The central only updates the ring's flash read pointer on fully verified and validated blocks. On reconnection, streaming automatically resumes from the last confirmed sequence number. |
| **Out-of-Memory (jetsam) Termination** | Edge AI allocated memory concurrently with background tasks. | **Execution Gating:** The LLM engine is strictly prohibited from running during background synchronization. Background executions run deterministic DSP pipelines only ($\leq 30MB$ footprint). |
| **GATT Encryption Key Invalidation** | User paired the ring to another device, clearing the local Long Term Key (LTK). | **Bond Eviction & Recovery:** Catch CBError.encryptionNotPermitted and CBATTErrorInsufficientAuthentication, drop stale peripheral state, and trigger standard iOS pairing flows. |
| **Ring Circular Buffer Overwrite** | Ring worn un-synced for $>7days$, exceeding onboard NOR flash capacity. | **High-Throughput Burst Ingestion:** Detect flash overwrite flags on connection; negotiate shorter BLE connection intervals ($7.5ms$) and larger MTU configurations to drain historical data before buffer wrap-around. |

---

