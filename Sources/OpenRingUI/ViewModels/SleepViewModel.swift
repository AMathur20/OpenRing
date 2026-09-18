import SwiftUI
import OpenRingCore
import OpenRingStorage

/// MainActor-isolated ViewModel coordinating the Sleep Architecture View (Tab 2).
@MainActor
public final class SleepViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var sleepScore: Int = 0
    @Published public private(set) var sleepTitle: String = "No Sleep Data"
    @Published public private(set) var durationSeconds: Int = 0
    @Published public private(set) var durationString: String = "0h 0m"
    @Published public private(set) var efficiencyRatio: Double = 0.0
    @Published public private(set) var efficiencyPercentage: Int = 0
    
    @Published public private(set) var deepSleepSeconds: Int = 0
    @Published public private(set) var remSleepSeconds: Int = 0
    @Published public private(set) var lightSleepSeconds: Int = 0
    @Published public private(set) var awakeSeconds: Int = 0
    
    @Published public private(set) var lowestHeartRate: Int = 0
    @Published public private(set) var averageHeartRate: Double = 0.0
    @Published public private(set) var averageRmssd: Double = 0.0
    @Published public private(set) var temperatureDeviation: Double = 0.0
    
    @Published public private(set) var hypnogramEpochs: [HypnogramEpoch] = []
    @Published public var selectedEpoch: HypnogramEpoch? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var hasSleepSession: Bool = false
    
    // MARK: - Dependencies
    
    private let database: DatabaseService
    
    // MARK: - Initialization
    
    public init(database: DatabaseService) {
        self.database = database
    }
    
    // MARK: - Data Loading
    
    public func loadLatestSleep() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            if let episode = try await database.fetchLatestSleepEpisode() {
                applyEpisode(episode)
                hasSleepSession = true
                await loadHypnogramData(for: episode)
            } else {
                hasSleepSession = false
                sleepScore = 0
                sleepTitle = "Pair Ring to Begin"
            }
        } catch {
            hasSleepSession = false
        }
    }
    
    public func applyEpisode(_ episode: SleepEpisodeRecord) {
        self.durationSeconds = episode.durationSeconds
        let hours = episode.durationSeconds / 3600
        let minutes = (episode.durationSeconds % 3600) / 60
        self.durationString = "\(hours)h \(minutes)m"
        
        self.efficiencyRatio = episode.efficiencyRatio
        self.efficiencyPercentage = Int(round(episode.efficiencyRatio * 100.0))
        
        self.deepSleepSeconds = episode.deepSleepSeconds
        self.remSleepSeconds = episode.remSleepSeconds
        self.lightSleepSeconds = episode.lightSleepSeconds
        self.awakeSeconds = episode.awakeSeconds
        
        self.lowestHeartRate = episode.lowestHeartRate
        self.averageHeartRate = episode.averageHeartRate
        self.averageRmssd = episode.averageRmssd
        self.temperatureDeviation = episode.temperatureDeviation
        
        // Calculate deterministic sleep score
        let score = SignalProcessor.computeSleepScore(
            durationSeconds: episode.durationSeconds,
            efficiencyRatio: episode.efficiencyRatio,
            deepSleepSeconds: episode.deepSleepSeconds,
            remSleepSeconds: episode.remSleepSeconds
        )
        self.sleepScore = score
        self.sleepTitle = Theme.sleepTierTitle(for: score)
    }
    
    private func loadHypnogramData(for episode: SleepEpisodeRecord) async {
        do {
            let samples = try await database.fetchBiometrics(
                from: episode.startTime,
                to: episode.endTime
            )
            
            // Transform samples into hypnogram epochs using heuristic or recorded stage
            var epochs: [HypnogramEpoch] = []
            for sample in samples {
                let date = Date(timeIntervalSince1970: Double(sample.timestamp) / 1000.0)
                let stage = SignalProcessor.classifySleepStageHeuristic(
                    heartRateBpm: sample.heartRateBpm,
                    baselineRhr: averageHeartRate > 0 ? averageHeartRate : 60.0,
                    motionIntensity: sample.motionIntensity
                )
                epochs.append(HypnogramEpoch(timestamp: date, stage: stage))
            }
            self.hypnogramEpochs = epochs
        } catch {
            self.hypnogramEpochs = []
        }
    }
    
    public func setDirectEpochs(_ epochs: [HypnogramEpoch]) {
        self.hypnogramEpochs = epochs
    }
}
