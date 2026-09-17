import Foundation

/// A low-level Oura protocol frame consisting of a 1-byte tag, a 1-byte length, and the payload bytes.
public struct Packet: Sendable, Equatable {
    public let tag: UInt8
    public let payload: Data
    
    public init(tag: UInt8, payload: Data = Data()) {
        self.tag = tag
        self.payload = payload
    }
    
    /// Encodes the packet into wire format: `[Tag, Length, Payload...]`.
    public func encode() -> Data {
        var data = Data(capacity: 2 + payload.count)
        data.append(tag)
        data.append(UInt8(payload.count & 0xFF))
        data.append(payload)
        return data
    }
    
    /// Parses a single packet from bytes.
    public static func parse(from data: Data) -> Packet? {
        guard data.count >= 2 else { return nil }
        let tag = data[data.startIndex]
        let declaredLen = Int(data[data.startIndex + 1])
        let payloadStart = data.startIndex + 2
        let payloadEnd = payloadStart + declaredLen
        
        let payload: Data
        if data.count >= payloadEnd {
            payload = data.subdata(in: payloadStart..<payloadEnd)
        } else {
            // Lenient parsing: ring occasionally sends frames with mismatched length byte
            payload = data.subdata(in: payloadStart..<data.endIndex)
        }
        return Packet(tag: tag, payload: payload)
    }
    
    /// Parses multiple concatenated packets from a single BLE notification buffer.
    /// Rings often concatenate multiple `tag | length | payload` frames into one BLE notification.
    public static func parseMany(from data: Data) -> [Packet] {
        var packets: [Packet] = []
        var index = data.startIndex
        
        while index + 2 <= data.endIndex {
            let tag = data[index]
            let len = Int(data[index + 1])
            let start = index + 2
            let end = start + len
            
            if end > data.endIndex {
                break
            }
            
            let payload = data.subdata(in: start..<end)
            packets.append(Packet(tag: tag, payload: payload))
            index = end
        }
        
        // Fallback: If strict parsing found none but we have at least 2 bytes, attempt lenient single parse
        if packets.isEmpty, let single = parse(from: data) {
            packets.append(single)
        }
        
        return packets
    }
    
    /// Returns the extended operation sub-tag if this packet has outer tag 0x2f.
    public var extendedTag: UInt8? {
        guard tag == 0x2f, !payload.isEmpty else { return nil }
        return payload[payload.startIndex]
    }
    
    /// Indicates if this packet represents an asynchronous history telemetry event (tag >= 0x41).
    public var isHistoryEvent: Bool {
        return tag >= GATTConstants.historyEventPrefixTag
    }
}

// MARK: - Protocol Request Builders

public enum OuraProtocolRequests {
    /// Get firmware / API / bootloader / BT-stack version (Command 0x08).
    public static func firmware() -> Data {
        return Data([0x08, 0x03, 0x00, 0x00, 0x00])
    }
    
    /// Get battery status (Command 0x0C).
    public static func battery() -> Data {
        return Packet(tag: 0x0C).encode()
    }
    
    /// Request app-authentication challenge nonce (Extended Op 0x2F / Sub-op 0x2B).
    public static func authNonce() -> Data {
        return Data([0x2f, 0x01, 0x2b])
    }
    
    /// Submit encrypted challenge nonce for authentication (Extended Op 0x2F / Sub-op 0x2D).
    public static func authenticate(ciphertext: Data) -> Data {
        precondition(ciphertext.count == 16, "Ciphertext must be exactly 16 bytes")
        var payload = Data(capacity: 17)
        payload.append(0x2d)
        payload.append(ciphertext)
        return Packet(tag: 0x2f, payload: payload).encode()
    }
    
    /// Install 16-byte authentication key on a factory-reset ring (Command 0x24).
    public static func setAuthKey(_ key: Data) -> Data {
        precondition(key.count == 16, "Key must be exactly 16 bytes")
        return Packet(tag: 0x24, payload: key).encode()
    }
    
    /// Synchronize current UTC wall clock with ring RTC (Command 0x12).
    public static func syncTime(date: Date = Date(), timezoneHalfHours: Int8 = 0) -> Data {
        let unixSeconds = UInt64(date.timeIntervalSince1970)
        var payload = Data(capacity: 9)
        var leUnix = unixSeconds.littleEndian
        withUnsafeBytes(of: &leUnix) { payload.append(contentsOf: $0) }
        payload.append(UInt8(bitPattern: timezoneHalfHours))
        return Packet(tag: 0x12, payload: payload).encode()
    }
    
    /// Request history events buffer drain (Command 0x10).
    public static func getEvents(startTimestamp: UInt32 = 0, maxEvents: UInt8 = 16, flags: Int32 = -1) -> Data {
        var payload = Data(capacity: 9)
        var leTimestamp = startTimestamp.littleEndian
        var leFlags = flags.littleEndian
        withUnsafeBytes(of: &leTimestamp) { payload.append(contentsOf: $0) }
        payload.append(maxEvents)
        withUnsafeBytes(of: &leFlags) { payload.append(contentsOf: $0) }
        return Packet(tag: 0x10, payload: payload).encode()
    }
    
    /// Set feature mode (Command 0x22 / Sub-tag), e.g. for live daytime HR.
    public static func setFeatureMode(featureId: UInt8, mode: UInt8) -> Data {
        let payload = Data([featureId, mode])
        return Packet(tag: 0x22, payload: payload).encode()
    }
}

