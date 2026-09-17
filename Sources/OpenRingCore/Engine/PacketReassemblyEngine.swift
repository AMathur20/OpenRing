import Foundation

/// Swift 6 isolated actor responsible for deframing, reassembling, and buffering
/// incoming BLE chunks from the Oura Ring.
public actor PacketReassemblyEngine {
    private var buffer = Data()
    private var totalBytesIngested: Int = 0
    private var totalPacketsExtracted: Int = 0
    private var totalEventsExtracted: Int = 0
    
    public init() {}
    
    /// Ingests a new raw data chunk from a CoreBluetooth notification and extracts all complete packets.
    public func ingestChunk(_ chunk: Data) -> [Packet] {
        buffer.append(chunk)
        totalBytesIngested += chunk.count
        
        var extractedPackets: [Packet] = []
        var index = buffer.startIndex
        
        while index + 2 <= buffer.endIndex {
            let tag = buffer[index]
            let declaredLen = Int(buffer[index + 1])
            let payloadStart = index + 2
            let frameEnd = payloadStart + declaredLen
            
            // Check if the full declared frame has arrived
            guard frameEnd <= buffer.endIndex else {
                // Incomplete frame, wait for additional chunks
                break
            }
            
            let payload = buffer.subdata(in: payloadStart..<frameEnd)
            let packet = Packet(tag: tag, payload: payload)
            extractedPackets.append(packet)
            totalPacketsExtracted += 1
            
            index = frameEnd
        }
        
        // Remove processed bytes from buffer
        if index > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<index)
        }
        
        return extractedPackets
    }
    
    /// Ingests a raw chunk and directly returns all parsed history events.
    public func ingestAndExtractEvents(_ chunk: Data) -> [RingEvent] {
        let packets = ingestChunk(chunk)
        let events = packets.compactMap { packet -> RingEvent? in
            guard packet.isHistoryEvent else { return nil }
            return RingEvent.from(packet: packet)
        }
        totalEventsExtracted += events.count
        return events
    }
    
    /// Clears any unparsed remnants in the reassembly buffer (e.g. on disconnection).
    public func reset() {
        buffer.removeAll()
    }
    
    /// Returns current buffer metrics for diagnostics and testing.
    public func metrics() -> (bufferCount: Int, bytesIngested: Int, packetsExtracted: Int, eventsExtracted: Int) {
        return (buffer.count, totalBytesIngested, totalPacketsExtracted, totalEventsExtracted)
    }
}

