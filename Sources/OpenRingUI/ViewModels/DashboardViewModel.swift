import SwiftUI
import OpenRingCore
import OpenRingStorage

/// MainActor-isolated ViewModel coordinating the Readiness Dashboard (Tab 1).
@MainActor
public final class DashboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var readinessScore: Int = 0
    @Published public private(set) var readinessTitle: String = "No Data"
    @Published public private(set) var rhrValue: Int = 0
    @Published public private(set) var rhrBaseline: Int = 0
    @Published public private(set) var rhrDeltaString: String = "0 bpm"
    @Published public private(set) var rhrStatus: MetricDeltaStatus = .nominal
    
    @Published public private(set) var hrvValue: Int = 0
    @Published public private(set) var hrvBaseline: Int = 0
    @Published public private(set) var hrvDeltaString: String = "0%"
    @Published public private(set) var hrvStatus: MetricDeltaStatus = .nominal
    
    @Published public private(set) var sleepEfficiencyPct: Int = 0
    @Published public private(set) var sleepEfficiencyStatus: MetricDeltaStatus = .nominal
    
    @Published public private(set) var tempDeviation: Double = 0.0
    @Published public private(set) var tempDeltaString: String = "0.00 °C"
    @Published public private(set) var tempStatus: MetricDeltaStatus = .nominal
    
    @Published public private(set) var bleState: BLEConnectionState = .disconnected
    @Published public private(set) var ringBattery: Int?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var hasEvaluation: Bool = false
    
    // MARK: - Dependencies
    
    private let database: DatabaseService
    private let bleEngine: BLEEngine?
    
    // MARK: - Initialization
    
    public init(database: DatabaseService, bleEngine: BLEEngine? = nil) {
        self.database = database
        self.bleEngine = bleEngine
    }
    
    // MARK: - Actions & Refresh
    
    public func refresh(for date: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        
        let targetDate = date ?? defaultEvaluationDate()
        
        do {
            if let eval = try await database.fetchDailyEvaluation(for: targetDate) {
                applyEvaluation(eval)
                hasEvaluation = true
            } else if let latest = try await database.fetchLatestDailyEvaluation(before: nil) {
                applyEvaluation(latest)
                hasEvaluation = true
            } else {
                hasEvaluation = false
                readinessScore = 0
                readinessTitle = "Pair Ring to Begin"
            }
        } catch {
            hasEvaluation = false
        }
    }
    
    private func applyEvaluation(_ eval: DailyEvaluationRecord) {
        self.readinessScore = eval.readinessScore
        self.readinessTitle = Theme.scoreTierTitle(for: eval.readinessScore)
        self.rhrBaseline = Int(round(eval.rhrBaseline))
        self.hrvBaseline = Int(round(eval.hrvBaseline))
        
        // Calculate status and delta strings
        // In real evaluations, we compute delta against baseline
        let rhrDiff = rhrValue > 0 ? (rhrValue - rhrBaseline) : 0
        if rhrDiff > 4 {
            rhrDeltaString = "+\(rhrDiff) bpm"
            rhrStatus = .warning
        } else if rhrDiff < 0 {
            rhrDeltaString = "\(rhrDiff) bpm"
            rhrStatus = .optimal
        } else {
            rhrDeltaString = "Nominal"
            rhrStatus = .nominal
        }
        
        if hrvBaseline > 0 && hrvValue > 0 {
            let hrvPct = ((Double(hrvValue) - Double(hrvBaseline)) / Double(hrvBaseline)) * 100.0
            if hrvPct <= -15.0 {
                hrvDeltaString = String(format: "%.0f%%", hrvPct)
                hrvStatus = .warning
            } else if hrvPct >= 15.0 {
                hrvDeltaString = String(format: "+%.0f%%", hrvPct)
                hrvStatus = .optimal
            } else {
                hrvDeltaString = "Balanced"
                hrvStatus = .nominal
            }
        } else {
            hrvDeltaString = "Nominal"
            hrvStatus = .nominal
        }
        
        if tempDeviation >= 0.50 {
            tempDeltaString = String(format: "+%.2f °C", tempDeviation)
            tempStatus = .warning
        } else {
            tempDeltaString = String(format: "%+.2f °C", tempDeviation)
            tempStatus = .nominal
        }
        
        if sleepEfficiencyPct >= 85 {
            sleepEfficiencyStatus = .optimal
        } else if sleepEfficiencyPct >= 75 {
            sleepEfficiencyStatus = .nominal
        } else {
            sleepEfficiencyStatus = .warning
        }
    }
    
    public func updateVitals(rhr: Int, hrv: Int, efficiency: Int, temp: Double) {
        self.rhrValue = rhr
        self.hrvValue = hrv
        self.sleepEfficiencyPct = efficiency
        self.tempDeviation = temp
    }
    
    public func updateBLEState(_ state: BLEConnectionState, battery: Int? = nil) {
        self.bleState = state
        if let battery = battery {
            self.ringBattery = battery
        }
    }
    
    private func defaultEvaluationDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
