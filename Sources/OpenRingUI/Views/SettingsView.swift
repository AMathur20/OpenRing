import SwiftUI
import OpenRingCore
import OpenRingStorage

/// Tab 4: Unified Settings & Data Sovereignty View (DEC-006, DEC-014, DEC-018).
public struct SettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel
    
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // Section 1: Ring Hardware & BLE Connection
                Section("Ring Hardware & Connectivity") {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(bleStatusColor)
                        Text("Status")
                        Spacer()
                        Text(bleStatusTitle)
                            .foregroundColor(.secondary)
                    }
                    
                    if let battery = viewModel.ringBatteryLevel {
                        HStack {
                            Image(systemName: "battery.100")
                                .foregroundColor(Theme.optimal)
                            Text("Ring Battery")
                            Spacer()
                            Text("\(battery)%")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Button {
                        viewModel.triggerScan()
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text(viewModel.isScanning ? "Scanning for Ring..." : "Pair / Reconnect Ring")
                            Spacer()
                            if viewModel.isScanning {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                    }
                    .disabled(viewModel.isScanning)
                }
                
                // Section 2: Cryptographic Security & Keys
                Section("Cryptographic Handshake (AES-128)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active 16-Byte Secret Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(viewModel.currentKeyHex)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 2)
                    
                    Button("Import 16-Byte Hex Key...") {
                        viewModel.showingKeyImportSheet = true
                    }
                    
                    Button("Generate Random Key") {
                        viewModel.generateRandomKey()
                    }
                }
                
                // Section 3: Data Sovereignty & Zero-Telemetry Audit
                Section("Data Sovereignty & Air-Gapped Sandboxing") {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title2)
                            .foregroundColor(Theme.optimal)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("100% Offline & Air-Gapped")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text("App sandbox contains 0 network entitlements. No cloud telemetry, no analytics SDKs.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Text("Local Database Engine")
                        Spacer()
                        Text("SQLite 3.39+ (WAL Mode)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Biometric Samples Stored")
                        Spacer()
                        Text("\(viewModel.totalBiometricSamples)")
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Sleep Episodes Stored")
                        Spacer()
                        Text("\(viewModel.totalSleepEpisodes)")
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Database File Size")
                        Spacer()
                        Text("\(viewModel.databaseSizeKB) KB")
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Section 4: Data Portability & Export
                Section("Data Portability & Raw Export") {
                    Button {
                        Task {
                            _ = await viewModel.exportBiometricsToCSV()
                            viewModel.showingExportSheet = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "tablecells")
                            Text("Export Biometric Samples (CSV)")
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button {
                        Task {
                            _ = await viewModel.exportEvaluationsToJSON()
                            viewModel.showingExportSheet = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Export Daily Evaluations (JSON)")
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Section 5: AI Model Configuration (v2 Placeholder)
                Section("Edge AI Engine Model") {
                    HStack {
                        Text("Active Model")
                        Spacer()
                        Text("Llama-3.2-3B INT4")
                            .font(.subheadline)
                            .foregroundColor(Theme.nominal)
                    }
                    
                    HStack {
                        Text("Inference Acceleration")
                        Spacer()
                        Text("Apple Metal GPU")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Model swapping (e.g. Gemma-2-2B or custom GGUF models via Files app) is coming in OpenRing v2.0.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Section 6: About, Licenses & Credits
                Section("Open Source & Legal") {
                    HStack {
                        Text("License")
                        Spacer()
                        Text("GNU GPLv3 + App Store Exception")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink("Licenses & Credits") {
                        creditsView
                    }
                    
                    NavigationLink("Roadmap: v2 Workout Tracking") {
                        workoutRoadmapView
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $viewModel.showingKeyImportSheet) {
                keyImportSheet
            }
            .sheet(isPresented: $viewModel.showingExportSheet) {
                exportDataSheet
            }
            .alert("OpenRing", isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage ?? "")
            }
            .task {
                await viewModel.loadSettingsAndStats()
            }
        }
    }
    
    // MARK: - Sheets & Detail Views
    
    private var keyImportSheet: some View {
        NavigationStack {
            Form {
                Section("Enter 16-Byte Hexadecimal Key") {
                    TextField("32 hex characters (e.g. a1b2c3...)", text: $viewModel.importKeyInput)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                
                Section {
                    Button("Save Key") {
                        viewModel.importSecretKey()
                        viewModel.showingKeyImportSheet = false
                    }
                    .disabled(viewModel.importKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Import Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showingKeyImportSheet = false }
                }
            }
        }
    }
    
    private var exportDataSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Exported \(viewModel.exportFormat) Telemetry")
                    .font(.headline)
                
                ScrollView {
                    Text(viewModel.exportedDataString ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.secondaryBackground)
                        .cornerRadius(8)
                }
                
                if let exportText = viewModel.exportedDataString {
                    ShareLink(item: exportText) {
                        Label("Share / Save \(viewModel.exportFormat)", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.nominal)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(16)
            .navigationTitle("Export Data")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { viewModel.showingExportSheet = false }
                }
            }
        }
    }
    
    private var creditsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("OpenRing Sovereignty Project")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("OpenRing is built under the GNU General Public License Version 3 (GPLv3) with an explicit Section 7 Mobile Distribution Exception granting rights to distribute through the Apple App Store and Google Play Store while legally requiring all source code modifications to remain 100% free and open source.")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("Third-Party Acknowledgments")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("• **open_oura** (by Th0rgal): Essential protocol reverse engineering and hardware research.")
                    Text("• **llama.cpp** (by Georgi Gerganov & contributors): High-performance on-device Metal GPU tensor runtime.")
                    Text("• **Apple Accelerate**: Vectorized DSP (vDSP) signal processing.")
                    Text("• **Apple SQLite3**: Native Write-Ahead Logging embedded storage.")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("Licenses & Credits")
    }
    
    private var workoutRoadmapView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(Theme.optimal)
                    VStack(alignment: .leading) {
                        Text("Workout Tracking")
                            .font(.headline)
                        Text("Planned for OpenRing v2.0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("OpenRing v2.0 will introduce a dedicated 5th tab for real-time and post-activity workout tracking:")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("• **Live Heart Rate Tracking:** Continuous high-frequency optical PPG streaming during activities.")
                    Text("• **Activity Strain Score:** Heart rate zone distribution (Zones 1–5) and EPOC exertion modeling.")
                    Text("• **Automatic Workout Detection:** Motion intensity segmentation from ring accelerometer tags.")
                    Text("• **Custom GGUF Model Swapping:** User-selectable edge AI models via the iOS Files app.")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("v2 Roadmap")
    }
    
    // MARK: - Helpers
    
    private var bleStatusColor: Color {
        switch viewModel.bleState {
        case .connected: return Theme.optimal
        case .connecting, .authenticating, .discoveringServices: return Theme.strain
        case .error: return Theme.critical
        default: return .secondary
        }
    }
    
    private var bleStatusTitle: String {
        switch viewModel.bleState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .authenticating: return "Authenticating..."
        case .discoveringServices: return "Discovering..."
        case .scanning: return "Scanning..."
        case .error(let msg): return "Error: \(msg)"
        default: return "Disconnected"
        }
    }
}
