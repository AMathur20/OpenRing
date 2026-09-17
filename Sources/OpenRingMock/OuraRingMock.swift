import Foundation
import CoreBluetooth
import OpenRingCore

/// Virtual Oura Ring BLE Peripheral simulator running on macOS / iOS.
/// Advertises GATT Service 0x98ED and simulates the challenge-response authentication
/// handshake and history event buffer streaming.
public final class OuraRingMock: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    
    private var peripheralManager: CBPeripheralManager?
    private var writeCharacteristic: CBMutableCharacteristic?
    private var notifyCharacteristic: CBMutableCharacteristic?
    
    private let activeKey: Data
    private var pendingChallengeNonce: Data?
    private let generator = MockDataGenerator()
    
    public var isAdvertising: Bool = false
    public var onLog: (@Sendable (String) -> Void)?
    
    public init(authKey: Data? = nil) {
        if let key = authKey, key.count == 16 {
            self.activeKey = key
        } else {
            // Default 16-byte testing key (0x01, 0x02, ... 0x10)
            self.activeKey = Data((1...16).map { UInt8($0) })
        }
        super.init()
    }
    
    public func start() {
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    public func stop() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        isAdvertising = false
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            log("CBPeripheralManager powered ON. Setting up Oura GATT Services...")
            setupServices()
        case .poweredOff:
            log("Bluetooth powered OFF")
            isAdvertising = false
        case .unauthorized:
            log("Bluetooth unauthorized")
        case .unsupported:
            log("Bluetooth unsupported on this hardware")
        default:
            break
        }
    }
    
    private func setupServices() {
        guard let manager = peripheralManager else { return }
        
        let writeChar = CBMutableCharacteristic(
            type: GATTConstants.writeUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        self.writeCharacteristic = writeChar
        
        let notifyChar = CBMutableCharacteristic(
            type: GATTConstants.notifyUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        self.notifyCharacteristic = notifyChar
        
        let service = CBMutableService(type: GATTConstants.serviceUUID, primary: true)
        service.characteristics = [writeChar, notifyChar]
        
        manager.add(service)
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if let error = error {
            log("Failed to add service: \(error.localizedDescription)")
            return
        }
        
        log("Service 0x98ED added successfully. Starting BLE advertisement...")
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [GATTConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "Oura Ring Gen3 Mock"
        ])
    }
    
    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if let error = error {
            log("Failed to start advertising: \(error.localizedDescription)")
            isAdvertising = false
        } else {
            log("Advertising as 'Oura Ring Gen3 Mock' on GATT 98ed0001-a541-11e4-b6a0-0002a5d5c51b")
            isAdvertising = true
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard let data = request.value, !data.isEmpty else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                continue
            }
            
            handleIncomingWrite(data: data)
            peripheral.respond(to: request, withResult: .success)
        }
    }
    
    private func handleIncomingWrite(data: Data) {
        log("Received write: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // Check for Auth Nonce Request: [0x2f, 0x01, 0x2b]
        if data == Data([0x2f, 0x01, 0x2b]) {
            let nonce = generator.generateAuthChallengeNonce()
            self.pendingChallengeNonce = nonce
            log("Generated 15-byte challenge nonce. Emitting notify challenge...")
            
            var challengePayload = Data([0x2c]) // sub-tag for nonce response
            challengePayload.append(nonce)
            let challengePacket = Packet(tag: 0x2f, payload: challengePayload)
            sendNotification(challengePacket.encode())
            return
        }
        
        // Check for Auth Response: Packet 0x2f, sub-tag 0x2d + 16-byte ciphertext
        if data.count == 19 && data[0] == 0x2f && data[1] == 0x11 && data[2] == 0x2d {
            let ciphertext = data.subdata(in: 3..<19)
            log("Received 16-byte auth response ciphertext. Verifying...")
            
            do {
                let decryptedNonce = try OuraAuthCrypto.decryptCiphertext(ciphertext, key: activeKey)
                if let expected = pendingChallengeNonce, decryptedNonce.prefix(expected.count) == expected {
                    log("Handshake SUCCESS! Auth result: 0x00")
                    let successPacket = Packet(tag: 0x2f, payload: Data([0x2e, 0x00]))
                    sendNotification(successPacket.encode())
                } else {
                    log("Handshake FAILED: Nonce mismatch")
                    let failPacket = Packet(tag: 0x2f, payload: Data([0x2e, 0x01]))
                    sendNotification(failPacket.encode())
                }
            } catch {
                log("Handshake Decryption error: \(error.localizedDescription)")
                let failPacket = Packet(tag: 0x2f, payload: Data([0x2e, 0x01]))
                sendNotification(failPacket.encode())
            }
            return
        }
        
        // Check for Get Events Request: Tag 0x10
        if data.first == 0x10 {
            log("Received GetEvents request. Streaming synthetic telemetry frames...")
            let stream = generator.generateFullNightStream()
            sendNotification(stream)
            return
        }
    }
    
    private func sendNotification(_ data: Data) {
        guard let manager = peripheralManager, let notifyChar = notifyCharacteristic else { return }
        let success = manager.updateValue(data, for: notifyChar, onSubscribedCentrals: nil)
        if !success {
            log("updateValue returned false (transmit queue full or no subscribed central)")
        }
    }
    
    private func log(_ message: String) {
        let formatted = "[OuraRingMock] \(message)"
        print(formatted)
        onLog?(formatted)
    }
}

