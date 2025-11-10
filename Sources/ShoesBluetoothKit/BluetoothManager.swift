//
//  File.swift
//  ShoesBluetoothKit
//
//  Created by Adesh Newaskar on 04/11/25.
//

import Foundation
import CoreBluetooth
import Combine

public final class BluetoothManager: NSObject, ObservableObject {
    public static let shared = BluetoothManager()
    public weak var delegate: BluetoothManagerDelegate?
    private var centralManager: CBCentralManager!
    public var deviceCharacteristics: [CBPeripheral: CBCharacteristic] = [:]
    var cancellables = Set<AnyCancellable>()
    
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var connectedDevices: [CBPeripheral] = []
    @Published public var observalAllowToSendData: Bool = false
    @Published public var leftBattery : Int?
    @Published public var rightBattery : Int?
    //@Published public private(set) var leftShoeData: Data?
    //@Published public private(set) var rightShoeData: Data?
    
    public let connectionSubject = PassthroughSubject<CBPeripheral, Never>()
    public var callWebSocket = PassthroughSubject<Void, Never>()
    public var callWebSocketDisconnect = PassthroughSubject<Void, Never>()
    public var leftShoeDataPublisher = PassthroughSubject<Data, Never>()
    public var rightShoeDataPublisher = PassthroughSubject<Data, Never>()
    
    private var reconnectQueue = DispatchQueue(label: "ReconnectQueue")
    private var arrDataDeviceName = ["own-l", "own-r"]
    
    private var isLogoutApplication : Bool = false
    private var isPairingNewDevice : Bool = false
    public var hasExecutedleftShoesOnce : Bool = false
    public var allowToSendData : Bool = false
    private var pairedManually : Bool = false
    public var isPeripheralConnectable: Bool = true
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main,options: [CBCentralManagerOptionRestoreIdentifierKey: "BluetoothRestoreID"])
    }
    
    public func updateLogoutState(_ value: Bool) {
        isLogoutApplication = value
        print("🔐 isLogoutApplication updated to \(value)")
    }
    
    public func updatePairingState(_ value: Bool) {
        isPairingNewDevice = value
        print("🔐 isPairingNewDevice value updated to \(value)")
    }
    public func hasExecutedleftShoes(_ value: Bool) {
        hasExecutedleftShoesOnce = value
        print("🔐 hasExecutedleftShoesOnce value updated to \(value)")
    }
    public func updateSendData(_ value: Bool) {
        allowToSendData = value
        print("🔐 allowToSendData value updated to \(value)")
    }
    public func updatepairedManually(_ value: Bool) {
        pairedManually = value
        print("🔐 pairedManually value updated to \(value)")
    }
    
    // MARK: - Public Methods
    public func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    public func stopScanning() {
        centralManager.stopScan()
    }
    
    public func connect(to peripheral: CBPeripheral) {
        centralManager.connect(peripheral, options: nil)
    }
    
    public func disconnect(from peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    public func disconnectAllDevices() {
        connectedDevices.forEach { centralManager.cancelPeripheralConnection($0) }
        connectedDevices.removeAll()
    }
    
    public func logout() {
        isLogoutApplication = true
        forceLogoutCleanup()
    }
    
    public func forceLogoutCleanup() {
        print("🔌 Force logout cleanup started")
        
        
        //leftCounter = 0
        //rightCounter = 0
        stopScanning()
        disconnectAllDevices()
        
        connectedDevices.removeAll()
        discoveredDevices.removeAll()
        deviceCharacteristics.removeAll()
        hasExecutedleftShoesOnce = false
        
        observalAllowToSendData = false
        //leftShoesRawData = nil
        //rightShoesRawData = nil
        
        leftBattery = 0
        rightBattery = 0
        
        // Disconnect WebSocket
        callWebSocketDisconnect.send(())
        
        print("🔌 Force logout cleanup complete")
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        print("Restoring Bluetooth state...")
        
        if isLogoutApplication == true{
            print("Skipping restore because user is logging out")
            return
        }
        // Skip auto-reconnect if pairing new device
        
        if isPairingNewDevice {
            print("⚠️ Skipping restore because user is pairing a new device")
            return
        }
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                print("Restored peripheral Name: \(peripheral.name ?? "Unknown")")
                if let name = peripheral.name?.lowercased() {
                    let lowercasedArr = arrDataDeviceName.map { $0.lowercased() }
                    if lowercasedArr.contains(where: { name.contains($0) }) {
                        peripheral.delegate = self
                        if delegate?.bluetoothManager(self, shouldConnectTo: peripheral) ?? true {
                            central.connect(peripheral, options: nil)
                            if !connectedDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                                connectedDevices.append(peripheral)
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth powered ON")
            if isLogoutApplication == true{
                print("🧹 Cleaning up due to logout on Bluetooth re-enable")
                //                forceLogoutCleanup()
                return // Don’t scan or connect
            }
            startScanning()
        case .poweredOff:
            print("Bluetooth powered OFF")
            // Optional: stop scanning and disconnect devices
            stopScanning()
            allowToSendData = false
            hasExecutedleftShoesOnce = false
            //            twoShoesPaired = false
            observalAllowToSendData = false
            
        default:
            print("Bluetooth state changed: \(central.state.rawValue)")
        }
    }
    //Test for all bluetooth devices
//        public func centralManager(_ central: CBCentralManager,
//                                   didDiscover peripheral: CBPeripheral,
//                                   advertisementData: [String : Any],
//                                   rssi RSSI: NSNumber) {
//    
//            if isLogoutApplication == true{
//                print("Skipping reconnect due to logout")
//                return
//            }
//    
//    
//            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unknown"
//                guard name.lowercased() != "unknown" else { return }
//                
//                if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
//                    let device = DiscoveredDevice(peripheral: peripheral, name: name, isConnected: false)
//                    discoveredDevices.append(device)
//                    print("🟦 Discovered device: \(name) (RSSI: \(RSSI))")
//                }
//    
//        }
    
    
    
    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String : Any],
                               rssi RSSI: NSNumber) {
        
        var matchedByServiceData = false
        var advertisedServiceStrings = [String]()
        
        // 1️⃣ Extract service data
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (uuid, data) in serviceData {
                // Try UTF-8
                if let stringValue = String(data: data, encoding: .utf8) {
                    advertisedServiceStrings.append(stringValue)
                    print("Advertised UUID 1: \(uuid), Data String: \(stringValue)")
                } else {
                    // Hex fallback
                    let hexString = "0x" + data.map { String(format: "%02x", $0) }.joined()
                    advertisedServiceStrings.append(hexString)
                    print("Advertised UUID 2: \(uuid), Data: \(hexString)")
                }
            }
            
            // 2️⃣ Check if any advertised string matches your target array
            for advertisedString in advertisedServiceStrings {
                if arrDataDeviceName.contains(where: { advertisedString.lowercased().contains($0.lowercased()) }) {
                    matchedByServiceData = true
                    print("✅ Matched Service Data: \(advertisedString)")
                    break
                }
            }
        }
        
        // 3️⃣ Also read advertised service UUIDs
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            print("Advertised UUID 3: \(serviceUUIDs)")
        }
        
        // 4️⃣ Handle name logic
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        ?? peripheral.name
        ?? "Unknown"
        
        let lowercasedName = advertisedName.lowercased()
        guard !lowercasedName.contains("unknown") else { return }
        
        guard !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) else { return }
        
        print("Discovered: \(advertisedName) - RSSI: \(RSSI)")
        
        let newDevice = DiscoveredDevice(peripheral: peripheral, name: advertisedName, isConnected: false)
        discoveredDevices.append(newDevice)
        
        /// 🔴 Add this guard to prevent reconnect on logout:
        if isLogoutApplication == true{
            print("Skipping reconnect due to logout")
            return
        }
        
        if isPairingNewDevice {
            print("⚠️ Skipping restore because user is pairing a new device")
            return
        }
        // 5️⃣ Connect based on match condition
        if lowercasedName.contains("own") {
                // ✅ Follow existing flow for "own" devices
                if matchedByServiceData || arrDataDeviceName.contains(where: { lowercasedName.contains($0.lowercased()) }) {
                    if connectedDevices.count <= 2, !pairedManually {
                        print("🔗 Connecting to \(advertisedName) (OWN device)")
                        central.connect(peripheral, options: nil)
                    }
                }
            } else {
                // 🔹 For non-OWN devices: connect normally so data can still be received
                print("🔹 Connecting to non-OWN device: \(advertisedName)")
                central.connect(peripheral, options: nil)
            }
    }
    
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        print("✅ Peripheral connected:", peripheral.name ?? "Unknown")
        
        if !connectedDevices.contains(peripheral) {
            connectedDevices.append(peripheral)
            
            if connectedDevices.count > 1 {
                print("✅ Both shoes connected — notifying ViewModel")
                callWebSocket.send(())
            }
        }
        
        print("connectedDevices: \(connectedDevices.map { $0.name ?? "Unnamed" })")
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        print("didDisconnectPeripheral error: \(error)")
        connectedDevices.removeAll { $0.identifier == peripheral.identifier }
        hasExecutedleftShoesOnce = false // Reset for next connection
        allowToSendData = false
        
        
        if let nameLeft = peripheral.name?.lowercased(), nameLeft.contains("own-l") {
            print("own-l commented")
            //BatteryStatusViewModel.shared.leftBattery =  0
            //leftCounter = 0
        }
        if let nameRight = peripheral.name?.lowercased(), nameRight.contains("own-r") {
            print("own-r commented")
            //BatteryStatusViewModel.shared.rightBattery =  0
            //rightCounter = 0
        }
        
        /// 🔴 Add this guard to prevent reconnect on logout:
        if isLogoutApplication == true{
            print("Skipping reconnect due to logout")
            return
        }
        
        if isPairingNewDevice {
            print("⚠️ Skipping restore because user is pairing a new device")
            return
        }
        
        reconnect(peripheral: peripheral)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        reconnect(peripheral: peripheral)
    }
    private func reconnect(peripheral: CBPeripheral) {
        if isLogoutApplication {
            print("⛔️ Skipping reconnect because of logout")
            return
        }
        
        reconnectQueue.asyncAfter(deadline: .now() + 5) {
            print("🔄 Reconnecting to \(peripheral.name ?? "Unknown")")
            
            if let name = peripheral.name?.lowercased() {
                let lowercasedArr = self.arrDataDeviceName.map { $0.lowercased() }
                if lowercasedArr.contains(where: { name.contains($0) }) {
                    if self.delegate?.bluetoothManager(self, shouldConnectTo: peripheral) ?? true {
                        self.connect(to: peripheral)
                    }
                }
            }
        }
    }
    
    
}
extension BluetoothManager: CBPeripheralDelegate {
    //post connection
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            print("Service UUID:", service.uuid)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        for char in characteristics ?? [] {
            print("Characteristic UUID:", char.uuid, "Properties:", char.properties)
        }
        // Iterate over all characteristics
        for char in characteristics {
            peripheral.setNotifyValue(true, for: char)
            
            // Only handle writable characteristics
            guard char.properties.contains(.write) else { continue }
            
            // Save characteristic for this peripheral
            deviceCharacteristics[peripheral] = char
            
            // Find the connected device that matches this peripheral
            if let matchedDevice = connectedDevices.first(where: { $0.identifier == peripheral.identifier }) {
                if let name = matchedDevice.name?.lowercased() {
                    var command: String?
                    
                    if name.contains("own-l") {
                        command = "BPM"
                    } else if name.contains("own-r") {
                        command = "BPST"
                    }
                    
                    // Write command only once per peripheral if applicable
                    if let command = command {
                        let demoMessage = "Hello from iPhone 👟"
                        let dataToSend = Data(command.utf8)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.writeData(to: matchedDevice, characteristic: char, data: dataToSend)
                        }
                        print("✅ command Sent \(command) to \(name)")
                        print("📤 Sent demo data to \(name): \(demoMessage)")
                    }
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard error == nil, let valueData = characteristic.value else { return }
        guard let stringValue = String(data: valueData, encoding: .utf8) else { return }
        
        if peripheral.name?.lowercased().contains("own-l") == true {
            //leftShoeData = data
            leftShoeDataPublisher.send(valueData) // 🔹 Send to project
            
            if !hasExecutedleftShoesOnce {
                //                sendWriteCommandtoLeftShoes()
                hasExecutedleftShoesOnce = true
            }
            let batteryLeft = extractBT(from:valueData)
            leftBattery = batteryLeft ?? 0
            //BatteryStatusViewModel.shared.leftBattery = batteryLeft ?? 0
            print("stringValue Left: \(stringValue)")
            print("batteryLeft: \(batteryLeft)")
            
            
            
        } else if peripheral.name?.lowercased().contains("own-r") == true {
            //rightShoeData = data
            
            let batteryRight = extractBT(from:valueData)
            rightBattery = batteryRight ?? 0
            print("stringValue Right: \(stringValue)")
            print("batteryRight: \(batteryRight)")
            
            rightShoeDataPublisher.send(valueData) // 🔹 Send to project
        }
    }
    
    func writeData(to peripheral: CBPeripheral, characteristic: CBCharacteristic, data: Data) {
        
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        //        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        peripheral.writeValue(data, for: characteristic, type: writeType)
        
    }
    func extractBT(from jsonData: Data) -> Int? {
        if let topLevel = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            if let bt = topLevel["BT"] as? Int {
                hasExecutedleftShoesOnce = true
                return bt
            } else if let data = topLevel["Data"] as? [String: Any],
                      let bt = data["BT"] as? Int {
                hasExecutedleftShoesOnce = false
                return bt
            }
        }
        return nil
    }
}

public protocol BluetoothManagerDelegate: AnyObject {
    func bluetoothManager(_ manager: BluetoothManager, shouldConnectTo peripheral: CBPeripheral) -> Bool
}


// MARK: - Model
//public struct DiscoveredDevice: Identifiable, Equatable {
//    public let id = UUID()
//    public let peripheral: CBPeripheral
//    public var name: String?
//    public var isConnected: Bool
//
//    public init(peripheral: CBPeripheral, name: String?, isConnected: Bool) {
//        self.peripheral = peripheral
//        self.name = name
//        self.isConnected = isConnected
//    }
//
//    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
//        lhs.peripheral.identifier == rhs.peripheral.identifier
//    }
//}

@objc public class DiscoveredDevice: NSObject {
    public let peripheral: CBPeripheral
    public var name: String?
    public var isConnected: Bool = false
    
    public init(peripheral: CBPeripheral, name: String?, isConnected: Bool) {
        self.peripheral = peripheral
        self.name = name
        self.isConnected = isConnected
        
    }
}

