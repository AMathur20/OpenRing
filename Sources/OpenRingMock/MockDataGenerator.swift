import Foundation
import OpenRingCore

/// Generator of realistic synthetic Oura Ring telemetry streams for headless testing,
/// simulator development, and protocol verification.
public final class MockDataGenerator: Sendable {
    
    public init() {}
    
    /// Creates a simulated 15-byte random challenge nonce for app-level authentication.
    public func generateAuthChallengeNonce() -> Data {
        var nonce = Data(count: 15)
        for i in 0..<15 {
            nonce[i] = UInt8.random(in: 0...255)
        }
        return nonce
    }
    
    /// Generates a synthetic 5-minute HRV history event packet (Tag 0x5D).
    public func generateHrvEventPacket(timestampDeciseconds: UInt32, avgHeartRate: UInt8 = 52, avgRmssd: UInt8 = 65) -> Packet {
        var payload = Data(capacity: 6)
        var leTimestamp = timestampDeciseconds.littleEndian
        withUnsafeBytes(of: &leTimestamp) { payload.append(contentsOf: $0) }
        payload.append(avgHeartRate)
        payload.append(avgRmssd)
        return Packet(tag: 0x5D, payload: payload)
    }
    
    /// Generates a synthetic nocturnal temperature packet (Tag 0x46) with samples in centi-Celsius.
    public func generateTemperatureEventPacket(timestampDeciseconds: UInt32, temperaturesCelsius: [Double] = [33.45, 33.52, 33.60, 33.48]) -> Packet {
        var payload = Data(capacity: 4 + (temperaturesCelsius.count * 2))
        var leTimestamp = timestampDeciseconds.littleEndian
        withUnsafeBytes(of: &leTimestamp) { payload.append(contentsOf: $0) }
        
        for temp in temperaturesCelsius {
            var rawInt16 = Int16(round(temp * 100.0)).littleEndian
            withUnsafeBytes(of: &rawInt16) { payload.append(contentsOf: $0) }
        }
        return Packet(tag: 0x46, payload: payload)
    }
    
    /// Generates a synthetic sleep phase hypnogram packet (Tag 0x4B) containing 2-bit stage codes.
    public func generateSleepPhasePacket(timestampDeciseconds: UInt32, stages: [SleepStage] = [.light, .deep, .deep, .rem, .light, .awake]) -> Packet {
        var payload = Data()
        var leTimestamp = timestampDeciseconds.littleEndian
        withUnsafeBytes(of: &leTimestamp) { payload.append(contentsOf: $0) }
        
        // Pack 4 stages per byte
        var currentByte: UInt8 = 0
        var bitOffset = 0
        
        for stage in stages {
            let code: UInt8
            switch stage {
            case .deep: code = 0
            case .light: code = 1
            case .rem: code = 2
            case .awake: code = 3
            case .unknown: code = 1
            }
            currentByte |= (code << bitOffset)
            bitOffset += 2
            
            if bitOffset == 8 {
                payload.append(currentByte)
                currentByte = 0
                bitOffset = 0
            }
        }
        if bitOffset > 0 {
            payload.append(currentByte)
        }
        
        return Packet(tag: 0x4B, payload: payload)
    }
    
    /// Generates a complete synthetic night session stream of concatenated packets.
    public func generateFullNightStream(baseTimestamp: UInt32 = 1715000000) -> Data {
        var streamData = Data()
        
        // 1. Time sync event
        var timeSyncPayload = Data()
        var leTs = baseTimestamp.littleEndian
        withUnsafeBytes(of: &leTs) { timeSyncPayload.append(contentsOf: $0) }
        streamData.append(Packet(tag: 0x42, payload: timeSyncPayload).encode())
        
        // 2. Series of 5-minute intervals across 7 hours (84 intervals)
        for i in 0..<84 {
            let deciseconds = baseTimestamp + UInt32(i * 3000) // 3000 deciseconds = 300 seconds = 5 min
            
            // HRV
            let hr = UInt8(50 + (i % 8))
            let rmssd = UInt8(68 - (i % 12))
            let hrvPacket = generateHrvEventPacket(timestampDeciseconds: deciseconds, avgHeartRate: hr, avgRmssd: rmssd)
            streamData.append(hrvPacket.encode())
            
            // Temperature
            let tempDeviation = 33.2 + (Double(i % 5) * 0.1)
            let tempPacket = generateTemperatureEventPacket(timestampDeciseconds: deciseconds, temperaturesCelsius: [tempDeviation])
            streamData.append(tempPacket.encode())
            
            // Sleep stages (cycling)
            let stage: SleepStage = (i < 10) ? .light : (i < 30 ? .deep : (i < 50 ? .rem : (i < 80 ? .light : .awake)))
            let sleepPacket = generateSleepPhasePacket(timestampDeciseconds: deciseconds, stages: [stage])
            streamData.append(sleepPacket.encode())
        }
        
        return streamData
    }
}

