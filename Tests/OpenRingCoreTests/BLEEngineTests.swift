import Foundation
import CoreBluetooth
@testable import OpenRingCore

/// Test suite verifying the BLEEngine actor state machine, request generation, and packet handling.
public struct BLEEngineTests: Sendable {
    
    public static func runTests(runTest: @MainActor (String, () async throws -> Void) async -> Void) async {
        print("\n--- [6] BLEEngine Central State Machine & Streams ---")
        
        await runTest("BLEEngine initializes with valid 16-byte key") {
            let key = Data(repeating: 0x01, count: 16)
            let engine = BLEEngine(authKey: key)
            
            let initialState = await engine.state
            assert(initialState == .disconnected, "Initial state should be disconnected")
        }
        
        await runTest("BLEEngine streams and state transition verification") {
            let key = Data((1...16).map { UInt8($0) })
            let engine = BLEEngine(authKey: key)
            
            // Verify streams are accessible and active
            let _ = engine.states
            let _ = engine.events
            let _ = engine.discoveredRings
            
            let state = await engine.state
            assert(state == .disconnected)
        }
        
        await runTest("BLEEngine history request & time sync builders") {
            let key = Data(repeating: 0xFF, count: 16)
            let _ = BLEEngine(authKey: key)
            
            // Verify getEvents packet structure matches spec
            let getEventsData = OuraProtocolRequests.getEvents(startTimestamp: 1000, maxEvents: 8)
            assert(getEventsData.count == 11) // 1 tag + 1 len + 4 ts + 1 max + 4 flags
            assert(getEventsData[0] == 0x10)
            assert(getEventsData[1] == 9)
            
            // Verify time sync packet structure matches spec
            let syncData = OuraProtocolRequests.syncTime()
            assert(syncData.count == 11) // 1 tag + 1 len + 8 unix + 1 tz
            assert(syncData[0] == 0x12)
            assert(syncData[1] == 9)
        }
        
        await runTest("BLEEngine handles incoming challenge nonce notification") {
            let key = Data((1...16).map { UInt8($0) })
            let engine = BLEEngine(authKey: key)
            
            let nonce = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F])
            let noncePacket = Packet(tag: 0x2F, payload: Data([0x2C]) + nonce)
            
            await engine.handleIncomingNotification(data: noncePacket.encode())
            let pending = await engine.pendingChallengeNonce
            assert(pending == nonce, "BLEEngine should record pending challenge nonce")
        }
        
        await runTest("BLEEngine handles authentication success packet") {
            let key = Data((1...16).map { UInt8($0) })
            let engine = BLEEngine(authKey: key)
            
            let authSuccess = Packet(tag: 0x2F, payload: Data([0x2E, 0x00]))
            await engine.handleIncomingNotification(data: authSuccess.encode())
            
            let state = await engine.state
            assert(state == .connected(authenticated: true), "State must be connected(authenticated: true)")
        }
        
        await runTest("BLEEngine handles authentication failure packet") {
            let key = Data((1...16).map { UInt8($0) })
            let engine = BLEEngine(authKey: key)
            
            let authFail = Packet(tag: 0x2F, payload: Data([0x2E, 0x01]))
            await engine.handleIncomingNotification(data: authFail.encode())
            
            let state = await engine.state
            if case .error(let msg) = state {
                assert(msg.contains("authenticationError") || msg.contains("failed"), "Expected error state")
            } else {
                fatalError("Expected error state but got \(state)")
            }
        }
        
        await runTest("BLEEngine routes incoming history packets to events stream") {
            let key = Data((1...16).map { UInt8($0) })
            let engine = BLEEngine(authKey: key)
            
            // Listen on events stream in background Task
            let eventExpectation = Task<RingEvent?, Never> {
                for await event in engine.events {
                    return event
                }
                return nil
            }
            
            // Ingest HRV telemetry packet (Tag 0x5D, timestamp 400000 deciseconds, HR 54, RMSSD 62)
            let hrvPayload = Data([0x80, 0x1A, 0x06, 0x00, 54, 62])
            let packet = Packet(tag: 0x5D, payload: hrvPayload)
            await engine.handleIncomingNotification(data: packet.encode())
            
            // Await yielded event
            let receivedEvent = await eventExpectation.value
            assert(receivedEvent != nil, "Events stream should yield decoded event")
            assert(receivedEvent?.tag == 0x5D, "Event tag should be 0x5D")
            assert(receivedEvent?.timestampDeciseconds == 400000, "Timestamp mismatch")
            if case .hrv(let samples) = receivedEvent?.payload {
                assert(samples.count == 1, "Expected 1 HRV sample")
                assert(samples[0].averageHeartRateBpm == 54)
                assert(samples[0].averageRmssdMs == 62)
            } else {
                fatalError("Expected .hrv payload")
            }
        }
    }
}

