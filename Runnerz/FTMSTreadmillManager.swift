import CoreBluetooth
import Foundation

final class FTMSTreadmillManager: NSObject, ObservableObject {
    struct Treadmill: Identifiable, Hashable {
        let id: UUID
        let name: String
    }

    @Published var speedKph = 0.0
    @Published var distanceMeters = 0.0
    @Published var inclinePercent = 0.0
    @Published var caloriesKcal = 0.0
    @Published private(set) var connectionText = "Looking for treadmill"
    @Published private(set) var treadmills: [Treadmill] = []
    @Published private(set) var isConnected = false

    private let serviceUUID = CBUUID(string: "1826")
    private let treadmillDataUUID = CBUUID(string: "2ACD")
    private let controlPointUUID = CBUUID(string: "2AD9")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlPoint: CBCharacteristic?
    private var peripherals: [UUID: CBPeripheral] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard central.state == .poweredOn else { return }
        central.stopScan()

        if isConnected, let peripheral {
            treadmills.removeAll { $0.id != peripheral.identifier }
            peripherals = peripherals.filter { $0.key == peripheral.identifier }
        } else {
            treadmills.removeAll()
            peripherals.removeAll()
            peripheral = nil
            controlPoint = nil
        }

        central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        if !isConnected {
            connectionText = "Looking for treadmill"
        }
    }

    func connect(to treadmill: Treadmill) {
        guard let peripheral = peripherals[treadmill.id] else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        isConnected = false
        connectionText = "Connecting"
        central.connect(peripheral)
    }

    func startTreadmill() {
        writeControlPoint([0x07])
    }

    func pauseTreadmill(paused: Bool) {
        writeControlPoint(paused ? [0x08, 0x00] : [0x07])
    }

    func stopTreadmill() {
        writeControlPoint([0x08, 0x01])
    }

    private func writeControlPoint(_ bytes: [UInt8]) {
        guard let peripheral, let controlPoint else { return }
        peripheral.writeValue(Data(bytes), for: controlPoint, type: .withResponse)
    }
}

extension FTMSTreadmillManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { startScanning() }
        else { connectionText = "Bluetooth unavailable" }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                       advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        if !treadmills.contains(where: { $0.id == peripheral.identifier }) {
            treadmills.append(Treadmill(id: peripheral.identifier,
                                        name: peripheral.name ?? "Unnamed treadmill"))
        }
        if self.peripheral == nil {
            connectionText = "Treadmill found"
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionText = "Finding treadmill controls"
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionText = "Connection failed"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        controlPoint = nil
        connectionText = "Disconnected"
        startScanning()
    }
}

extension FTMSTreadmillManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach { peripheral.discoverCharacteristics([treadmillDataUUID, controlPointUUID], for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil {
            isConnected = false
            connectionText = "Connection failed"
            return
        }
        service.characteristics?.forEach { characteristic in
            if characteristic.uuid == treadmillDataUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == controlPointUUID {
                controlPoint = characteristic
                isConnected = true
                connectionText = "Connected"
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == treadmillDataUUID, let data = characteristic.value else { return }
        parse(data)
    }

    private func parse(_ data: Data) {
        guard data.count >= 2 else { return }
        let flags = UInt16(data[0]) | UInt16(data[1]) << 8
        var offset = 2

        func take(_ count: Int) -> Data? {
            guard offset + count <= data.count else { return nil }
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }
        func u16(_ bytes: Data) -> UInt16 { UInt16(bytes[0]) | UInt16(bytes[1]) << 8 }
        func i16(_ bytes: Data) -> Int16 { Int16(bitPattern: u16(bytes)) }

        if flags & 0x0001 == 0, let bytes = take(2) {
            speedKph = Double(u16(bytes)) / 100
        }
        if flags & 0x0002 != 0 { _ = take(2) }
        if flags & 0x0004 != 0, let bytes = take(3) {
            distanceMeters = Double(bytes[0]) + Double(bytes[1]) * 256 + Double(bytes[2]) * 65536
        }
        if flags & 0x0008 != 0, let bytes = take(2) {
            inclinePercent = Double(i16(bytes)) / 10
        }
        if flags & 0x0010 != 0 { _ = take(2) }
        if flags & 0x0020 != 0 { _ = take(2) }
        if flags & 0x0040 != 0 { _ = take(2) }
        if flags & 0x0080 != 0 { _ = take(2) }
        if flags & 0x0100 != 0 { _ = take(2) }
        if flags & 0x0200 != 0 { _ = take(2) }
        if flags & 0x0400 != 0 { _ = take(2) }
        if flags & 0x0800 != 0 { _ = take(2) }
        if flags & 0x1000 != 0, let bytes = take(2) {
            caloriesKcal = Double(u16(bytes))
        }
        if flags & 0x2000 != 0 { _ = take(2) }
        if flags & 0x4000 != 0 { _ = take(2) }
        if flags & 0x8000 != 0 { _ = take(1) }
    }
}
