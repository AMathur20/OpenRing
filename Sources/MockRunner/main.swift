import Foundation
import OpenRingCore
import OpenRingMock

print("=====================================================")
print(" OpenRing Virtual BLE Peripheral & Telemetry Harness ")
print("=====================================================")
print("Starting Oura Ring Gen 3 GATT Simulator...")
print("GATT Service: \(GATTConstants.serviceUUID)")
print("Write Char:   \(GATTConstants.writeUUID)")
print("Notify Char:  \(GATTConstants.notifyUUID)")
print("Press Ctrl+C to stop.")

let mock = OuraRingMock()
mock.start()

RunLoop.main.run()

