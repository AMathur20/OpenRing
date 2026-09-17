import Foundation
import CoreBluetooth

/// GATT UUIDs and protocol constants for Oura Ring communication.
/// Reverse-engineered from Oura Ring Gen 3 and validated across Ring 3/4/5 hardware.
public enum GATTConstants {
    /// Primary Oura Nordic GATT Service UUID.
    public static let serviceUUID = CBUUID(string: "98ed0001-a541-11e4-b6a0-0002a5d5c51b")
    
    /// Write characteristic — protocol commands and authentication writes are sent here.
    public static let writeUUID = CBUUID(string: "98ed0002-a541-11e4-b6a0-0002a5d5c51b")
    
    /// Read/Notify characteristic — command acknowledgments and async history telemetry streams arrive here.
    public static let notifyUUID = CBUUID(string: "98ed0003-a541-11e4-b6a0-0002a5d5c51b")
    
    /// Standard Bluetooth SIG Battery Service.
    public static let batteryServiceUUID = CBUUID(string: "180F")
    /// Standard Battery Level Characteristic (0-100%).
    public static let batteryLevelUUID = CBUUID(string: "2A19")
    
    /// Standard Bluetooth SIG Device Information Service.
    public static let deviceInformationServiceUUID = CBUUID(string: "180A")
    /// Firmware Revision String Characteristic.
    public static let firmwareRevisionUUID = CBUUID(string: "2A26")
    /// Manufacturer Name Characteristic.
    public static let manufacturerNameUUID = CBUUID(string: "2A29")
    /// Model Number Characteristic.
    public static let modelNumberUUID = CBUUID(string: "2A24")
    
    /// History event prefix boundary. All packet tags >= 0x41 represent history telemetry events.
    public static let historyEventPrefixTag: UInt8 = 0x41
}

