import Foundation
import CoreBluetooth

/// Connection and authentication states for the Oura Ring BLE connection.
public enum BLEConnectionState: Sendable, Equatable {
    case poweredOff
    case unauthorized
    case unsupported
    case disconnected
    case scanning
    case connecting
    case discoveringServices
    case authenticating
    case connected(authenticated: Bool)
    case error(String)
}

/// Discovered peripheral metadata.
public struct DiscoveredRing: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    
    public init(id: UUID, name: String, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

/// Swift 6 isolated actor coordinating Bluetooth Low Energy discovery, GATT connections,
/// background state restoration, automated session authentication, and telemetry streaming.
public actor BLEEngine {
    
    // MARK: - State & Dependencies
    
    public private(set) var state: BLEConnectionState = .disconnected {
        didSet {
            stateContinuation?.yield(state)
        }
    }
    
    private let authKey: Data
    private let reassemblyEngine = PacketReassemblyEngine()
    
    // CoreBluetooth Bridge
    private var bridge: BLECentralBridge?
    private var activePeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    // Async Streams
    private var stateContinuation: AsyncStream<BLEConnectionState>.Continuation?
    public nonisolated let states: AsyncStream<BLEConnectionState>
    
    private var eventContinuation: AsyncStream<RingEvent>.Continuation?
    public nonisolated let events: AsyncStream<RingEvent>
    
    private var discoveryContinuation: AsyncStream<DiscoveredRing>.Continuation?
    public nonisolated let discoveredRings: AsyncStream<DiscoveredRing>
    
    // Handshake Tracker
    public private(set) var pendingChallengeNonce: Data?
    
    // MARK: - Initialization
    
    public init(authKey: Data) {
        precondition(authKey.count == 16, "Auth key must be exactly 16 bytes")
        self.authKey = authKey
        
        var sCont: AsyncStream<BLEConnectionState>.Continuation?
        self.states = AsyncStream { sCont = $0 }
        self.stateContinuation = sCont
        
        var eCont: AsyncStream<RingEvent>.Continuation?
        self.events = AsyncStream { eCont = $0 }
        self.eventContinuation = eCont
        
        var dCont: AsyncStream<DiscoveredRing>.Continuation?
        self.discoveredRings = AsyncStream { dCont = $0 }
        self.discoveryContinuation = dCont
    }
    
    /// Starts the underlying CBCentralManager.
    public func start(restoreIdentifier: String? = "OpenRingCentralRestoreID") {
        guard bridge == nil else { return }
        self.bridge = BLECentralBridge(engine: self, restoreIdentifier: restoreIdentifier)
    }
    
    // MARK: - Public Control APIs
    
    /// Starts scanning for nearby Oura rings targeting the primary Nordic service 0x98ED.
    public func startScanning() {
        guard let bridge = bridge, bridge.isPoweredOn else {
            state = .error("Bluetooth central manager is not powered on")
            return
        }
        state = .scanning
        bridge.startScanning()
    }
    
    /// Stops scanning for peripherals.
    public func stopScanning() {
        bridge?.stopScanning()
        if state == .scanning {
            state = .disconnected
        }
    }
    
    /// Connects to a specific discovered ring by its CoreBluetooth identifier.
    public func connect(to identifier: UUID) {
        state = .connecting
        bridge?.connect(to: identifier)
    }
    
    /// Disconnects the active peripheral and resets the reassembly engine.
    public func disconnect() {
        bridge?.disconnect()
        activePeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        pendingChallengeNonce = nil
        Task {
            await reassemblyEngine.reset()
        }
        state = .disconnected
    }
    
    /// Triggers an asynchronous history telemetry flash dump (Command 0x10).
    public func requestHistorySync(startTimestamp: UInt32 = 0, maxEvents: UInt8 = 16) {
        let request = OuraProtocolRequests.getEvents(startTimestamp: startTimestamp, maxEvents: maxEvents)
        sendRawData(request)
    }
    
    /// Requests battery percentage (Command 0x0C).
    public func requestBatteryStatus() {
        let request = OuraProtocolRequests.battery()
        sendRawData(request)
    }
    
    /// Synchronizes the ring clock with current UTC time (Command 0x12).
    public func synchronizeClock(date: Date = Date()) {
        let request = OuraProtocolRequests.syncTime(date: date)
        sendRawData(request)
    }
    
    /// Sends raw byte payload to the ring write characteristic.
    public func sendRawData(_ data: Data) {
        guard let peripheral = activePeripheral, let writeChar = writeCharacteristic else {
            return
        }
        let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: writeChar, type: writeType)
    }
    
    // MARK: - Internal Delegate Handlers (invoked via BLECentralBridge)
    
    fileprivate func handleCentralStateChange(poweredOn: Bool, authStatus: CBManagerAuthorization, stateDescription: String) {
        if !poweredOn {
            switch authStatus {
            case .denied, .restricted:
                state = .unauthorized
            default:
                state = .poweredOff
            }
        } else if state == .poweredOff || state == .unauthorized {
            state = .disconnected
        }
    }
    
    fileprivate func handleDiscoveredPeripheral(identifier: UUID, name: String, rssi: Int) {
        discoveryContinuation?.yield(DiscoveredRing(id: identifier, name: name, rssi: rssi))
    }
    
    fileprivate func handleConnected(peripheral: CBPeripheral) {
        self.activePeripheral = peripheral
        self.state = .discoveringServices
        peripheral.discoverServices([GATTConstants.serviceUUID])
    }
    
    fileprivate func handleDisconnected(error: (any Error)?) {
        activePeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        pendingChallengeNonce = nil
        Task {
            await reassemblyEngine.reset()
        }
        if let error = error {
            state = .error("Disconnected: \(error.localizedDescription)")
        } else {
            state = .disconnected
        }
    }
    
    fileprivate func handleDiscoveredCharacteristics(service: CBService) {
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            if char.uuid == GATTConstants.writeUUID {
                self.writeCharacteristic = char
            } else if char.uuid == GATTConstants.notifyUUID {
                self.notifyCharacteristic = char
                // Subscribe to notifications
                self.activePeripheral?.setNotifyValue(true, for: char)
            }
        }
    }
    
    fileprivate func handleNotificationStateUpdated(characteristic: CBCharacteristic) {
        guard characteristic.uuid == GATTConstants.notifyUUID, characteristic.isNotifying else { return }
        
        // Notifications established: begin App-Level Authentication Handshake
        self.state = .authenticating
        let nonceRequest = OuraProtocolRequests.authNonce()
        sendRawData(nonceRequest)
    }
    
    public func handleIncomingNotification(data: Data) async {
        let packets = await reassemblyEngine.ingestChunk(data)
        for packet in packets {
            await processPacket(packet)
        }
    }
    
    private func processPacket(_ packet: Packet) async {
        // 1. Check for Authentication Challenge Nonce (0x2F ext 0x2C)
        if packet.tag == 0x2f, let extTag = packet.extendedTag, extTag == 0x2c {
            let nonce = packet.payload.subdata(in: 1..<packet.payload.count)
            self.pendingChallengeNonce = nonce
            
            do {
                let ciphertext = try OuraAuthCrypto.encryptNonce(nonce, key: authKey)
                let authResponse = OuraProtocolRequests.authenticate(ciphertext: ciphertext)
                sendRawData(authResponse)
            } catch {
                self.state = .error("Crypto error during auth challenge: \(error.localizedDescription)")
            }
            return
        }
        
        // 2. Check for Authentication Status Result (0x2F ext 0x2E)
        if packet.tag == 0x2f, let extTag = packet.extendedTag, extTag == 0x2e {
            let statusByte = packet.payload.count >= 2 ? packet.payload[1] : 0xFF
            let result = AuthResult(byte: statusByte)
            
            if result.isSuccess {
                self.state = .connected(authenticated: true)
                // Automatically sync time on successful connection
                synchronizeClock()
            } else {
                self.state = .error("Authentication failed with code: \(result)")
            }
            return
        }
        
        // 3. Process History Events (Tag >= 0x41)
        if packet.isHistoryEvent {
            let event = RingEvent.from(packet: packet)
            eventContinuation?.yield(event)
        }
    }
}

// MARK: - Private CoreBluetooth Bridge Class

/// Non-isolated delegate bridge forwarding CoreBluetooth delegate events to the `BLEEngine` actor.
private final class BLECentralBridge: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private unowned let engine: BLEEngine
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    
    var isPoweredOn: Bool {
        return centralManager.state == .poweredOn
    }
    
    init(engine: BLEEngine, restoreIdentifier: String?) {
        self.engine = engine
        super.init()
        
        var options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        if let restoreId = restoreIdentifier {
            options[CBCentralManagerOptionRestoreIdentifierKey] = restoreId
        }
        
        self.centralManager = CBCentralManager(
            delegate: self,
            queue: DispatchQueue(label: "org.openring.ble.central", qos: .userInitiated),
            options: options
        )
    }
    
    func startScanning() {
        centralManager.scanForPeripherals(
            withServices: [GATTConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    func stopScanning() {
        centralManager.stopScan()
    }
    
    func connect(to identifier: UUID) {
        guard let peripheral = discoveredPeripherals[identifier] else { return }
        stopScanning()
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }
    
    func disconnect() {
        for peripheral in discoveredPeripherals.values {
            if peripheral.state == .connected || peripheral.state == .connecting {
                centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let isPowered = (central.state == .poweredOn)
        let auth = CBCentralManager.authorization
        Task { [weak engine] in
            await engine?.handleCentralStateChange(
                poweredOn: isPowered,
                authStatus: auth,
                stateDescription: "\(central.state.rawValue)"
            )
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                discoveredPeripherals[peripheral.identifier] = peripheral
                peripheral.delegate = self
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Oura Ring"
        discoveredPeripherals[id] = peripheral
        peripheral.delegate = self
        
        Task { [weak engine] in
            await engine?.handleDiscoveredPeripheral(identifier: id, name: name, rssi: RSSI.intValue)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        Task { [weak engine] in
            await engine?.handleConnected(peripheral: peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        Task { [weak engine] in
            await engine?.handleDisconnected(error: error)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        Task { [weak engine] in
            await engine?.handleDisconnected(error: error)
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == GATTConstants.serviceUUID {
            peripheral.discoverCharacteristics([GATTConstants.writeUUID, GATTConstants.notifyUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        Task { [weak engine] in
            await engine?.handleDiscoveredCharacteristics(service: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task { [weak engine] in
            await engine?.handleNotificationStateUpdated(characteristic: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let data = characteristic.value, !data.isEmpty else { return }
        Task { [weak engine] in
            await engine?.handleIncomingNotification(data: data)
        }
    }
}
