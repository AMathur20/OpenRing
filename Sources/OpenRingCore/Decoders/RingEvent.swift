import Foundation

/// A single decoded history event from the Oura Ring circular flash buffer.
public struct RingEvent: Sendable, Equatable {
    public let tag: UInt8
    public let name: String
    /// Timestamp reported by the ring (in deciseconds, i.e., 1/10th of a second since ring epoch).
    public let timestampDeciseconds: UInt32
    /// Raw un-modified event body payload (excluding the 4-byte timestamp header).
    public let rawBody: Data
    /// Structured payload decode, or nil if using raw representation.
    public let payload: EventPayload
    
    public init(tag: UInt8, name: String, timestampDeciseconds: UInt32, rawBody: Data, payload: EventPayload) {
        self.tag = tag
        self.name = name
        self.timestampDeciseconds = timestampDeciseconds
        self.rawBody = rawBody
        self.payload = payload
    }
    
    /// Returns the approximate date computed from the timestamp (if aligned with Unix epoch).
    public var timestampDate: Date {
        // Ring deciseconds are 100ms units
        let seconds = Double(timestampDeciseconds) / 10.0
        return Date(timeIntervalSince1970: seconds)
    }
    
    /// Constructs and decodes a RingEvent from a raw protocol Packet.
    public static func from(packet: Packet) -> RingEvent {
        let tag = packet.tag
        let p = packet.payload
        
        let timestamp: UInt32
        let body: Data
        if p.count >= 4 {
            timestamp = p.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: 0, as: UInt32.self).littleEndian
            }
            body = p.subdata(in: 4..<p.count)
        } else {
            timestamp = 0
            body = p
        }
        
        let (name, payload) = decodeEventBody(tag: tag, body: body)
        return RingEvent(
            tag: tag,
            name: name,
            timestampDeciseconds: timestamp,
            rawBody: body,
            payload: payload
        )
    }
    
    /// Dispatches decoding for known Oura history event tags.
    public static func decodeEventBody(tag: UInt8, body: Data) -> (String, EventPayload) {
        switch tag {
        case 0x41:
            // Boot event: [u32 reason][u8 unknown][fw a.b.c][bootloader a.b.c][api a.b.c]
            let reason: UInt32 = body.count >= 4 ? body.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian } : 0
            var fwString = "unknown"
            if body.count >= 8 {
                fwString = "\(body[5]).\(body[6]).\(body[7])"
            }
            return ("ring_start", .ringStart(reason: reason, firmware: fwString))
            
        case 0x42:
            // Time sync: u32 LE Unix timestamp
            let unix = body.count >= 4 ? body.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian } : 0
            return ("time_sync", .timeSync(unixSeconds: unix))
            
        case 0x46, 0x69, 0x75:
            // Temperatures: series of i16 LE centi-Celsius
            var temps: [Double] = []
            if body.count >= 2 && body.count % 2 == 0 {
                body.withUnsafeBytes { ptr in
                    let count = body.count / 2
                    for i in 0..<count {
                        let raw = ptr.loadUnaligned(fromByteOffset: i * 2, as: Int16.self).littleEndian
                        let celsius = Double(raw) / 100.0
                        if celsius >= -40.0 && celsius <= 85.0 {
                            temps.append(round(celsius * 100.0) / 100.0)
                        }
                    }
                }
            }
            let name = (tag == 0x46 ? "temp_event" : (tag == 0x69 ? "temp_period" : "sleep_temp"))
            return (name, .temperature(temperaturesCelsius: temps))
            
        case 0x5D:
            // HRV: pairs of (u8 avg_hr, u8 avg_rmssd) per 5-minute interval
            var samples: [HRVSample] = []
            if body.count >= 2 && body.count % 2 == 0 {
                var i = body.startIndex
                while i + 1 < body.endIndex {
                    let hr = body[i]
                    let rmssd = body[i + 1]
                    samples.append(HRVSample(averageHeartRateBpm: hr, averageRmssdMs: rmssd))
                    i += 2
                }
            }
            return ("hrv_event", .hrv(samples: samples))
            
        case 0x4B, 0x4E, 0x5A:
            // Sleep stages: 2-bit hypnogram codes, 4 stages per byte
            var stages: [SleepStage] = []
            for byte in body {
                stages.append(SleepStage(twoBitCode: (byte >> 0) & 0x03))
                stages.append(SleepStage(twoBitCode: (byte >> 2) & 0x03))
                stages.append(SleepStage(twoBitCode: (byte >> 4) & 0x03))
                stages.append(SleepStage(twoBitCode: (byte >> 6) & 0x03))
            }
            let name = (tag == 0x4B ? "sleep_phase_info" : (tag == 0x4E ? "sleep_phase_details" : "sleep_phase_data"))
            return (name, .sleepPhases(stages: stages))
            
        case 0x80:
            // Green IBI + quality: pairs of bytes (ibi_ms = (b1 & 7) | (b0 << 3), q = (b1 >> 3) & 3)
            var ibis: [UInt16] = []
            var qualities: [UInt8] = []
            if body.count >= 2 && body.count % 2 == 0 {
                var i = body.startIndex
                while i + 1 < body.endIndex {
                    let b0 = body[i]
                    let b1 = body[i + 1]
                    let ibi = (UInt16(b1 & 0x07)) | (UInt16(b0) << 3)
                    let q = (b1 >> 3) & 0x03
                    ibis.append(ibi)
                    qualities.append(q)
                    i += 2
                }
            }
            return ("green_ibi_quality", .interBeatIntervals(ibiMs: ibis, quality: qualities))
            
        case 0x47, 0x6B, 0x72:
            // Motion events: scaled motion intensity values
            var intensities: [Double] = []
            for byte in body {
                intensities.append(Double(byte))
            }
            let name = (tag == 0x47 ? "motion_event" : (tag == 0x6B ? "motion_period" : "sleep_acm_period"))
            return (name, .motion(intensityValues: intensities))
            
        default:
            return ("unknown_0x\(String(format: "%02X", tag))", .raw(bytes: body))
        }
    }
}

