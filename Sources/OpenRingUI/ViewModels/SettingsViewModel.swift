import SwiftUI
import OpenRingCore
import OpenRingStorage

/// MainActor-isolated ViewModel coordinating Settings and Data Sovereignty (Tab 4, DEC-018).
@MainActor
public final class SettingsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    // BLE & Hardware
    @Published public private(set) var bleState: BLEConnectionState = .disconnected
    @Published public private(set) var connectedRingName: String?
    @Published public private(set) var ringBatteryLevel: Int?
    @Published public private(set) var isScanning: Bool = false
    
    // Cryptography & Pairing Key
    @Published public private(set) var currentKeyHex: String = "••••••••••••••••••••••••••••••••"
    @Published public var importKeyInput: String = ""
    @Published public private(set) var keyStatusMessage: String?
    
    // Data Sovereignty & SQLite WAL Stats
    @Published public private(set) var totalBiometricSamples: Int = 0
    @Published public private(set) var totalSleepEpisodes: Int = 0
    @Published public private(set) var totalDailyEvaluations: Int = 0
    @Published public private(set) var databaseSizeKB: Int = 0
    @Published public private(set) var zeroNetworkVerified: Bool = true
    
    // Export Status & Sheet Controls
    @Published public var showingKeyImportSheet: Bool = false
    @Published public var showingExportSheet: Bool = false
    @Published public private(set) var exportedDataString: String?
    @Published public private(set) var isExporting: Bool = false
    @Published public private(set) var exportFormat: String = "CSV"
    
    // Alerts & Messages
    @Published public var alertMessage: String?
    @Published public var showAlert: Bool = false
    
    // MARK: - Dependencies
    
    private let database: DatabaseService
    private let bleEngine: BLEEngine?
    
    // MARK: - Initialization
    
    public init(database: DatabaseService, bleEngine: BLEEngine? = nil) {
        self.database = database
        self.bleEngine = bleEngine
    }
    
    // MARK: - Lifecycle & Data Loading
    
    public func loadSettingsAndStats() async {
        do {
            let stats = try await database.fetchDatabaseStats()
            self.totalBiometricSamples = stats.biometricCount
            self.totalSleepEpisodes = stats.sleepCount
            self.totalDailyEvaluations = stats.evalCount
            self.databaseSizeKB = stats.sizeKB
        } catch {
            // Keep existing stats on failure
        }
    }
    
    // MARK: - BLE Actions
    
    public func triggerScan() {
        guard let engine = bleEngine else { return }
        isScanning = true
        Task {
            await engine.startScanning()
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self.isScanning = false
        }
    }
    
    public func disconnectRing() {
        guard let engine = bleEngine else { return }
        Task {
            await engine.disconnect()
        }
    }
    
    public func updateBLEState(_ state: BLEConnectionState, name: String? = nil, battery: Int? = nil) {
        self.bleState = state
        if let name = name {
            self.connectedRingName = name
        }
        if let battery = battery {
            self.ringBatteryLevel = battery
        }
    }
    
    // MARK: - AES-128 Key Provisioning
    
    public func importSecretKey() {
        let cleanHex = importKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        guard cleanHex.count == 32, OuraAuthCrypto.hexStringToData(cleanHex) != nil else {
            self.keyStatusMessage = "Invalid key: must be exactly 32 hex characters (16 bytes)."
            self.alertMessage = self.keyStatusMessage
            self.showAlert = true
            return
        }
        
        self.currentKeyHex = cleanHex
        self.keyStatusMessage = "16-byte cryptographic key imported successfully."
        self.importKeyInput = ""
        self.alertMessage = self.keyStatusMessage
        self.showAlert = true
    }
    
    public func generateRandomKey() {
        if let newKey = try? OuraAuthCrypto.generateRandomKey() {
            let hex = newKey.map { String(format: "%02x", $0) }.joined()
            self.currentKeyHex = hex
            self.keyStatusMessage = "Generated new random 16-byte pairing key."
            self.alertMessage = self.keyStatusMessage
            self.showAlert = true
        }
    }
    
    // MARK: - Data Export Serialization
    
    public func exportBiometricsToCSV() async -> String {
        isExporting = true
        defer { isExporting = false }
        
        do {
            let samples = try await database.fetchBiometrics(from: 0, to: Int64.max)
            var csv = "timestamp_ms,heart_rate_bpm,rmssd_ms,motion_intensity,signal_quality\n"
            for s in samples {
                csv.append("\(s.timestamp),\(s.heartRateBpm),\(s.rmssdMs),\(s.motionIntensity),\(s.ppgSignalQuality)\n")
            }
            self.exportedDataString = csv
            self.exportFormat = "CSV"
            return csv
        } catch {
            return "timestamp_ms,heart_rate_bpm,rmssd_ms,motion_intensity,signal_quality\n"
        }
    }
    
    public func exportEvaluationsToJSON() async -> String {
        isExporting = true
        defer { isExporting = false }
        
        do {
            let evals = try await database.fetchAllDailyEvaluations()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(evals), let jsonString = String(data: data, encoding: .utf8) {
                self.exportedDataString = jsonString
                self.exportFormat = "JSON"
                return jsonString
            }
            return "[]"
        } catch {
            return "[]"
        }
    }
}
