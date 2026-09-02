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
    @Published private(set) var connectionText = "Permissions required"
    @Published private(set) var treadmills: [Treadmill] = []
    @Published private(set) var isConnected = false
    @Published private(set) var isScanning = false

    private let serviceUUID = CBUUID(string: "1826")
    private let treadmillDataUUID = CBUUID(string: "2ACD")
    private let controlPointUUID = CBUUID(string: "2AD9")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var controlPoint: CBCharacteristic?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var authorizationContinuation: CheckedContinuation<Bool, Never>?
    private var scanningEnabled = false
    private var scanTimeoutTimer: Timer?
#if targetEnvironment(simulator)
    private static let simulatorTreadmillID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private var simulatorTimer: Timer?
#endif

    override init() {
        super.init()
    }

    func requestAuthorization() async -> Bool {
#if targetEnvironment(simulator)
        await MainActor.run {
            self.treadmills = [Treadmill(id: Self.simulatorTreadmillID, name: "Simulator treadmill")]
            self.connectionText = "Connected"
            self.isConnected = true
            self.startSimulatorTimer()
        }
        return true
#else
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            if central == nil {
                central = CBCentralManager(delegate: self, queue: .main)
            }
            resolveAuthorization()
            if authorizationContinuation != nil { startAuthorizationProbe() }
        }
#endif
    }

    func startScanning() {
#if targetEnvironment(simulator)
        scanTimeoutTimer?.invalidate()
        scanningEnabled = true
        isScanning = false
        treadmills = [Treadmill(id: Self.simulatorTreadmillID, name: "Simulator treadmill")]
        connectionText = "Connected"
        isConnected = true
        startSimulatorTimer()
        return
#else
        guard !isConnected,
              let central,
              CBManager.authorization == .allowedAlways,
              central.state == .poweredOn else { return }
        scanningEnabled = true
        isScanning = true
        central.stopScan()
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.scanningEnabled = false
            self.isScanning = false
            self.central?.stopScan()
            self.scanTimeoutTimer = nil
        }

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
#endif
    }

    func stopScanning() {
        scanningEnabled = false
        isScanning = false
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
#if targetEnvironment(simulator)
        return
#else
        central?.stopScan()
#endif
    }

    func connect(to treadmill: Treadmill) {
#if targetEnvironment(simulator)
        guard treadmill.id == Self.simulatorTreadmillID else { return }
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        isScanning = false
        connectionText = "Connected"
        isConnected = true
        return
#else
        guard let central, CBManager.authorization == .allowedAlways,
              let peripheral = peripherals[treadmill.id] else { return }
        scanningEnabled = false
        isScanning = false
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        isConnected = false
        connectionText = "Connecting"
        central.connect(peripheral)
#endif
    }

    func startTreadmill() {
#if targetEnvironment(simulator)
        if speedKph <= 0 { speedKph = 4.0 }
        startSimulatorTimer()
        return
#else
        writeControlPoint([0x07])
#endif
    }

    func pauseTreadmill(paused: Bool) {
#if targetEnvironment(simulator)
        if paused {
            speedKph = 0
        } else if speedKph <= 0 {
            speedKph = 4.0
        }
        startSimulatorTimer()
        return
#else
        writeControlPoint(paused ? [0x08, 0x00] : [0x07])
#endif
    }

    func stopTreadmill() {
#if targetEnvironment(simulator)
        speedKph = 0
        return
#else
        writeControlPoint([0x08, 0x01])
#endif
    }

#if targetEnvironment(simulator)
    func setSimulatorSpeed(_ speed: Double) {
        speedKph = max(0, speed)
        startSimulatorTimer()
    }

    func resetSimulatorTotals() {
        distanceMeters = 0
    }

    private func startSimulatorTimer() {
        guard simulatorTimer == nil else { return }
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.speedKph > 0 else { return }
            self.distanceMeters += self.speedKph / 3.6
        }
    }
#endif

    private func writeControlPoint(_ bytes: [UInt8]) {
        guard let peripheral, let controlPoint, CBManager.authorization == .allowedAlways else { return }
        peripheral.writeValue(Data(bytes), for: controlPoint, type: .withResponse)
    }

    private func startAuthorizationProbe() {
        guard let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
}

extension FTMSTreadmillManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        resolveAuthorization()
        if CBManager.authorization == .notDetermined {
            startAuthorizationProbe()
            return
        }
        guard CBManager.authorization == .allowedAlways else {
            connectionText = "Bluetooth access required"
            return
        }
        if central.state == .poweredOn, scanningEnabled {
            startScanning()
        } else if central.state != .poweredOn {
            connectionText = "Bluetooth unavailable"
        }
    }

    private func resolveAuthorization() {
        switch CBManager.authorization {
        case .allowedAlways:
            central?.stopScan()
            authorizationContinuation?.resume(returning: true)
            authorizationContinuation = nil
        case .denied, .restricted:
            central?.stopScan()
            connectionText = "Bluetooth access required"
            authorizationContinuation?.resume(returning: false)
            authorizationContinuation = nil
        case .notDetermined:
            break
        @unknown default:
            authorizationContinuation?.resume(returning: false)
            authorizationContinuation = nil
        }
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
        isScanning = false
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
        if flags & 0x1000 != 0 { _ = take(2) }
        if flags & 0x2000 != 0 { _ = take(2) }
        if flags & 0x4000 != 0 { _ = take(2) }
        if flags & 0x8000 != 0 { _ = take(1) }
    }
}
