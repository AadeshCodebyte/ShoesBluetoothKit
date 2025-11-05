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
    
    private var centralManager: CBCentralManager!
    
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    
    @Published public var connectedDevices: [CBPeripheral] = []
    @Published public private(set) var leftShoeData: Data?
    @Published public private(set) var rightShoeData: Data?
    
    public let connectionSubject = PassthroughSubject<CBPeripheral, Never>()
    
    
    public var deviceCharacteristics: [CBPeripheral: CBCharacteristic] = [:]
    var cancellables = Set<AnyCancellable>()
    
    public let leftShoeDataPublisher = PassthroughSubject<Data, Never>()
    public let rightShoeDataPublisher = PassthroughSubject<Data, Never>()

    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
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
}

extension BluetoothManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth powered ON")
        case .poweredOff:
            print("Bluetooth powered OFF")
            
        default:
            print("Bluetooth state changed: \(central.state.rawValue)")
        }
    }
//    public func centralManager(_ central: CBCentralManager,
//                               didDiscover peripheral: CBPeripheral,
//                               advertisementData: [String : Any],
//                               rssi RSSI: NSNumber) {
//        
//        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unknown"
//        
//        //     // ✅ Discover all Bluetooth devices (for testing)
//             let device = DiscoveredDevice(peripheral: peripheral, name: name, isConnected: false)
//             if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
//             discoveredDevices.append(device)
//             print("🟦 Discovered device: \(name)")
//             }
//        
//             }

    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unknown"
        guard name.lowercased().contains("own"), !name.lowercased().contains("unknown") else { return }
        
        let newDevice = DiscoveredDevice(peripheral: peripheral, name: name, isConnected: false)
        DispatchQueue.main.async {
            if !self.discoveredDevices.contains(newDevice) {
                self.discoveredDevices.append(newDevice)
            }
        }
    }
    
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDevices.append(peripheral)
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        print("Connected to \(peripheral.name ?? "Unknown")")
        //Notify the project about the connection
        connectionSubject.send(peripheral)
    }
    
    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        connectedDevices.removeAll { $0.identifier == peripheral.identifier }
        print("Disconnected: \(peripheral.name ?? "Unknown")")
    }
}
extension BluetoothManager: CBPeripheralDelegate {
    //post connection
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            peripheral.setNotifyValue(true, for: char)
            if char.properties.contains(.write) {
                deviceCharacteristics[peripheral] = char
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard let data = characteristic.value else { return }
        
        if peripheral.name?.lowercased().contains("own-l") == true {
            leftShoeData = data
            leftShoeDataPublisher.send(data) // 🔹 Send to project
        } else if peripheral.name?.lowercased().contains("own-r") == true {
            rightShoeData = data
            rightShoeDataPublisher.send(data) // 🔹 Send to project
        }
    }
    
    public func writeData(to peripheral: CBPeripheral, data: Data) {
        guard let characteristic = deviceCharacteristics[peripheral] else { return }
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write)
        ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }
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

