import Foundation

/// Sleep stages classified by the ring firmware.
public enum SleepStage: UInt8, Sendable, Codable, Equatable {
    case deep = 1
    case light = 2
    case rem = 3
    case awake = 4
    case unknown = 0
    
    public init(twoBitCode: UInt8) {
        switch twoBitCode & 0x03 {
        case 0: self = .deep
        case 1: self = .light
        case 2: self = .rem
        case 3: self = .awake
        default: self = .unknown
        }
    }
}

/// A 5-minute HRV telemetry window sample.
public struct HRVSample: Sendable, Codable, Equatable {
    public let averageHeartRateBpm: UInt8
    public let averageRmssdMs: UInt8
    
    public init(averageHeartRateBpm: UInt8, averageRmssdMs: UInt8) {
        self.averageHeartRateBpm = averageHeartRateBpm
        self.averageRmssdMs = averageRmssdMs
    }
}

/// Typed representations of decoded Oura history event payloads.
public enum EventPayload: Sendable, Codable, Equatable {
    /// 5-minute rolling HRV and resting heart rate averages (Tag 0x5D).
    case hrv(samples: [HRVSample])
    
    /// Skin temperature readings in degrees Celsius (Tags 0x46, 0x69, 0x75).
    case temperature(temperaturesCelsius: [Double])
    
    /// On-device sleep stage classifications (Tags 0x4B, 0x4E, 0x5A).
    case sleepPhases(stages: [SleepStage])
    
    /// High-resolution inter-beat intervals in milliseconds (Tags 0x44, 0x60, 0x80).
    case interBeatIntervals(ibiMs: [UInt16], quality: [UInt8])
    
    /// Accelerometer motion intensity (Tags 0x47, 0x6B, 0x72).
    case motion(intensityValues: [Double])
    
    /// Wall clock time sync timestamp anchor (Tag 0x42).
    case timeSync(unixSeconds: UInt32)
    
    /// Ring hardware boot record (Tag 0x41).
    case ringStart(reason: UInt32, firmware: String)
    
    /// Unclassified or proprietary event payload preserved raw and lossless.
    case raw(bytes: Data)
}

