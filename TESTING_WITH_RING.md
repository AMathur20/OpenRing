# OpenRing Physical Ring Testing Protocol (v0.1)

This document provides a comprehensive, step-by-step engineering guide for deploying **OpenRing v0.1** to a physical iPhone and verifying real-world Bluetooth Low Energy (BLE) discovery, cryptographic authentication, biometric telemetry ingestion, deterministic scoring, and on-device Edge AI inference with an actual **Oura Ring Gen 3** (Horizon or Heritage).

---

## Prerequisites & Equipment

1. **Hardware**:
   - **Oura Ring Gen 3** (Size 6–13, firmware 2.8.0+ recommended).
   - **Oura Charging Dock** with USB-C power connection.
   - **iPhone** running **iOS 17.0+** (iPhone 11 or newer; iPhone 15 Pro / 16 recommended for on-device Metal GPU LLM inference).
   - **Apple Mac** with **Xcode 15+** or **Xcode 16+** installed.
   - USB-C or Lightning cable to connect iPhone to Mac.
2. **Apple Developer Account**:
   - A free personal Apple ID is sufficient (no paid developer program required).
3. **Repository State**:
   - Bundled or downloaded GGUF weights: [`Models/Llama-3.2-3B-Instruct-Q4_K_M.gguf`](Models/Llama-3.2-3B-Instruct-Q4_K_M.gguf) (~1.9 GB).

---

## Step 1: Deploy OpenRing to Your Physical iPhone

1. **Connect Your iPhone to Your Mac**:
   - Attach your iPhone via cable and unlock the device.
   - If prompted on the iPhone, select **"Trust This Computer"** and enter your passcode.
2. **Enable Developer Mode on iOS** (iOS 16+ requirement):
   - On your iPhone, open **Settings > Privacy & Security > Developer Mode**.
   - Toggle **Developer Mode** to **ON**.
   - Your iPhone will reboot. After restarting, unlock and tap **"Turn On"** when prompted.
3. **Open the Project in Xcode**:
   - Open terminal on your Mac and navigate to the project directory:
     ```bash
     cd /path/to/openring
     open OpenRing.xcodeproj
     ```
4. **Configure Automatic Code Signing**:
   - In Xcode's left Project Navigator, select the root **`OpenRing`** project.
   - Under **Targets**, select **`OpenRing`**.
   - Open the **"Signing & Capabilities"** tab.
   - Ensure **"Automatically manage signing"** is checked.
   - In the **Team** dropdown, select your name (**Personal Team** with your Apple ID).
   - Bundle Identifier defaults to `org.openring.OpenRingApp` (or change prefix to unique string if necessary).
5. **Install and Run**:
   - In Xcode's top toolbar, select the destination dropdown (next to the Play button) and select your **physical iPhone** (e.g., *Ankur's iPhone*).
   - Press **Run** ($\mathbf{\Cmd + R}$) or click the **Play** button.
   - Xcode will compile `OpenRingCore`, `OpenRingStorage`, `OpenRingAI`, and `OpenRingUI`, bundle `Llama-3.2-3B-Instruct-Q4_K_M.gguf`, and install `OpenRing.app` directly onto your iPhone.
   - When the app launches on your iPhone, iOS will show a permission modal:
     > **"OpenRing Would Like to Use Bluetooth"**
     > *Tap **"Allow"**.*

---

## Step 2: Preparing Your Oura Ring for Pairing

Oura Ring Gen 3 uses a single-bonded BLE stack: it will only communicate with a central device that possesses its 16-byte AES-128 secret key. Follow the scenario matching your ring's current state:

### Scenario A: Unbonded Ring on Charger (Recommended)

If your ring has been factory reset or is unbonded:
1. **Place the Ring on the Charger**:
   - Place the ring on its USB-powered charging dock.
   - Ensure the charger LED pulses gently (white or light green).
   - Being on the charger keeps the ring in a high-power advertising state and ready for fresh cryptographic key provisioning.
2. **Launch OpenRing on Your iPhone**:
   - Switch to **Tab 4: Settings** in OpenRing.
   - The app will automatically scan for peripherals advertising the Nordic GATT service UUID `98ed0001-a541-11e4-b6a0-0002a5d5c51b` (named `Oura Ring Gen3 <XXXX>`).
   - If pairing a factory-unbonded ring, OpenRing generates a cryptographically secure 16-byte random key (`OuraAuthCrypto.generateRandomKey()`), provisions the key to the ring via Packet `0x24`, and stores it in local secure storage.
   - Within 3–5 seconds, the BLE status pill in the top header transitions to:
     $$\mathbf{\text{Connected (Authenticated)} \quad \checkmark}$$
   - The ring's battery percentage and peripheral name will populate in the header.

---

### Scenario B: Ring Currently Paired to the Official Oura App

If your ring is currently paired and in use with the official Oura iOS app:
1. **Option B1: Factory Reset via Official App (Cleanest)**:
   - In the official Oura app: go to **Settings > Back up all data** (wait for cloud sync to finish).
   - Tap **Settings > Factory Reset** (or tap the ring icon > Disconnect / Reset).
   - Place the ring on the charger.
   - Open iPhone **Settings > Bluetooth**, find your Oura Ring under "My Devices", tap the **(i)** icon, and tap **"Forget This Device"**.
   - Now follow **Scenario A** above using OpenRing.
2. **Option B2: Retaining Existing Secret Key (No Reset)**:
   - If you have previously extracted the 16-byte hex key from an Android backup or packet capture:
   - In OpenRing, navigate to **Tab 4: Settings > Secret Key Management**.
   - Tap **"Import 16-Byte Secret Key"**.
   - Paste the 32-character hexadecimal key (e.g., `4f2a7b...`) and tap **Save**.
   - Turn off Bluetooth on any other devices running the official Oura app to prevent GATT connection contention.
   - Tap **"Scan for Ring"**. OpenRing will execute the challenge-response handshake using the imported key and establish an authenticated session.

---

## Step 3: Verification of the Cryptographic Handshake

Navigate to **Tab 4: Settings** and verify the following live connection diagnostics:

1. **BLE State**: Confirms `Connected (Authenticated)`.
2. **Ring Battery Level**: Displays current percentage (e.g., `88%`).
3. **Secret Key Status**: Shows active key confirmation (`16-byte cryptographic key active`).
4. **Data Sovereignty Audit**:
   - **Zero-Network Architecture Badge**: Confirms `0 External Sockets Open`.
   - **Local Database Engine**: Confirms `SQLite 3.39+ (WAL Mode)`.
   - **Stored Records**: Confirms raw samples, sleep episodes, and evaluations stored strictly locally on device flash.

---

## Step 4: Wear Protocol & Telemetry Synchronization

1. **Put the Ring On**:
   - Remove the ring from the charger and slide it onto your finger (index, middle, or ring finger).
   - **Important**: Ensure the 3 sensor bumps are firmly positioned against the **palm side** (underside) of your finger for optimal PPG optical coupling.
2. **Wear for Telemetry Generation**:
   - **Quick Test (15–30 minutes)**: Walk around or sit quietly to generate immediate daytime heart rate, motion (accelerometer), and temperature samples.
   - **Full Night Sleep Test (Recommended)**: Wear the ring overnight. The ring continuously writes high-frequency photoplethysmography (PPG), inter-beat intervals (IBI), 3-axis accelerometer vectors, and negative temperature coefficient (NTC) thermistor samples into its internal NOR flash circular buffer.
3. **Morning Ingestion & Draining**:
   - When you wake up, open OpenRing on your iPhone within BLE range (~2–3 meters).
   - OpenRing automatically initiates the circular buffer download:
     - **Tag `0x5D` (`hrv_event`)**: Decodes 5-minute averaged heart rate and rMSSD values.
     - **Tag `0x46` (`temp_event`)**: Decodes nocturnal skin temperature readings in centi-°C.
     - **Tag `0x4B` (`hypnogram_event`)**: Decodes on-device sleep stage classifications (Deep, Light, REM, Awake).
   - The Lossless Archiver commits every raw frame into the SQLite `raw_ingestion_log` table before parsing into typed records.

---

## Step 5: End-to-End Verification Across All 4 Tabs

### Tab 1: Readiness Dashboard (`ReadinessDashboardView`)
* **Circular Score Gauge**: Displays your computed morning Readiness Score ($0–100$).
* **Recovery Tiers**: The gauge ring and background glow adapt dynamically based on physiological state:
  - **Optimal Recovery** ($\ge 85$): Emerald Green.
  - **Good Recovery** ($70–84$): Sky Blue.
  - **Moderate Strain** ($55–69$): Amber.
  - **Critical Rest Needed** ($< 55$): Coral Red.
* **Biometric Comparison Cards**:
  - **Resting Heart Rate (RHR)**: Compares nightly average against your 14-day rolling baseline with exact $\Delta\text{ bpm}$ pill.
  - **HRV (rMSSD)**: Compares parasympathetic tone against baseline with % delta indicator.
  - **Sleep Efficiency**: Reports ratio of actual sleep time to total time in bed.
  - **Thermal Deviation**: Reports temperature baseline offset in $\pm^\circ\text{C}$ (alerts when $> +0.50^\circ\text{C}$).

### Tab 2: Sleep Architecture (`SleepArchitectureView`)
* **Sleep Score Gauge**: Computes your deterministic Sleep Score ($0–100$, DEC-016) based on total sleep duration, efficiency, deep sleep, and REM sleep.
* **Interactive 60 FPS Hypnogram**:
  - Renders your full sleep stage timeline (Awake, REM, Light, Deep).
  - **Interactive Scrubbing**: Touch and drag your finger across the hypnogram chart to inspect specific epochs, exact clock times, and stage classifications in real time.
* **Stage Proportion Metrics**:
  - Confirms Deep Sleep duration (target $\ge 90\text{ min}$) and REM Sleep duration.
  - Confirms automatic heuristic fallback activation (DEC-011) if firmware reports contained intermittent gaps.

### Tab 3: Edge AI Recovery Coach (`RecoveryCoachView`)
* **On-Device LLM Synthesis**:
  - Tap **"Synthesize Recovery Protocol"**.
  - Observe the live **Typewriter Token Streaming** powered by the bundled `Llama-3.2-3B-Instruct` model running locally on your iPhone's Apple Neural Engine / Metal GPU.
* **Validation Criteria**:
  1. *Speed*: Yields tokens fluidly with zero lag.
  2. *Structure*: Formats exactly 3 paragraphs:
     - **Autonomic Load**: Interprets RHR and HRV vs your 14-day baseline.
     - **Sleep Architecture**: Evaluates restorative sleep proportions.
     - **Actionable Recovery Protocol**: Suggests functional adjustments for training, hydration, and wind-down timing.
  3. *Safety & Tone*: Non-diagnostic sports physiology advice strictly under 140 words; displays FDA SaMD disclaimer footer.
  4. *Offline Confirmation*: Put your iPhone in **Airplane Mode** (Wi-Fi and Cellular OFF, Bluetooth ON) and trigger synthesis to prove 100% offline edge inference!

### Tab 4: Settings & Data Sovereignty (`SettingsView`)
* **Data Portability & Export**:
  - Tap **"Export Biometrics (CSV)"**: Opens the iOS Share Sheet with your complete, uncompressed raw time-series ready to AirDrop, save to Files, or open in Python/Numbers/Excel.
  - Tap **"Export Daily Evaluations (JSON)"**: Generates structured JSON containing all scores, baselines, and AI syntheses.
* **Live Database Statistics**:
  - Inspect total biometric rows, sleep episodes, and database size in KB.

---

## Step 6: Troubleshooting & Edge Cases

| Issue | Root Cause | Solution |
| :--- | :--- | :--- |
| **Ring not discovered during scan** | Ring is asleep or battery is depleted | Place the ring on its USB charger. The charger LED will pulse, waking the ring into continuous BLE advertising mode. |
| **Bluetooth permission denied** | iOS permission was dismissed or denied | Open iPhone **Settings > Privacy & Security > Bluetooth**, find **OpenRing**, and ensure the toggle is **ON**. |
| **Authentication Rejected (Status `0x01`)** | Key mismatch between OpenRing and the ring | If the ring was previously bonded to another phone, factory-reset it on the charger, or re-import the known 16-byte key in Settings. |
| **Charger Hardware Reset (Hard Reset)** | Ring firmware in an unresponsive state | Place the ring on the charger. Tap the charger base firmly against a flat table 3 times within 2 seconds. The charger LED will flash to confirm a hardware reset. |
| **Another device steals connection** | Previous phone holds the GATT connection | Disable Bluetooth on the secondary phone or tablet that was previously paired with the Oura Ring. |
| **App Store / Developer Signing error** | Developer certificate untrusted | On iPhone, go to **Settings > General > VPN & Device Management**, tap your Apple ID under Developer App, and tap **"Trust"**. |

---

## Technical Support & Local Log Inspection

OpenRing includes an internal offline diagnostic logger. To inspect local SQLite transactions and BLE state machine transitions:
- In OpenRing **Settings**, tap **"View Local Diagnostic Logs"**.
- All log statements are generated with subsystem tags:
  - `[BLEEngine]`: Central state transitions, peripheral discovery, and GATT characteristics.
  - `[SyncCoordinator]`: Raw packet reassembly, sequence verification, and database commits.
  - `[SignalProcessor]`: vDSP rMSSD calculations, EMA updates, and score outputs.
  - `[LLMInferenceService]`: Metal GPU context allocation, prompt generation, and token throughput.
