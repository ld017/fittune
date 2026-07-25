import Foundation
import CoreBluetooth

struct BluetoothHeartRateMeasurement: Equatable {
    var bpm: Int
    var contactDetected: Bool?
    var energyExpendedKilojoules: Int?
    var rrIntervalsSeconds: [Double]
}

enum BluetoothHeartRateParserError: Error, Equatable {
    case incompletePayload
}

enum BluetoothHeartRateParser {
    static func parse(_ bytes: [UInt8]) throws -> BluetoothHeartRateMeasurement {
        guard bytes.count >= 2 else { throw BluetoothHeartRateParserError.incompletePayload }
        let flags = bytes[0]
        var index = 1
        let bpm: Int
        if flags & 0x01 != 0 {
            guard bytes.count >= index + 2 else { throw BluetoothHeartRateParserError.incompletePayload }
            bpm = Int(UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
            index += 2
        } else {
            bpm = Int(bytes[index])
            index += 1
        }

        let contactSupported = flags & 0x02 != 0
        let contactDetected: Bool? = contactSupported ? flags & 0x04 != 0 : nil
        var energy: Int?
        if flags & 0x08 != 0 {
            guard bytes.count >= index + 2 else { throw BluetoothHeartRateParserError.incompletePayload }
            energy = Int(UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
            index += 2
        }
        var rrIntervals: [Double] = []
        if flags & 0x10 != 0 {
            while bytes.count >= index + 2 {
                let raw = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
                rrIntervals.append(Double(raw) / 1024)
                index += 2
            }
        }
        return BluetoothHeartRateMeasurement(
            bpm: bpm,
            contactDetected: contactDetected,
            energyExpendedKilojoules: energy,
            rrIntervalsSeconds: rrIntervals
        )
    }
}

protocol BluetoothHeartRateProviding: AnyObject {
    var onDiscovery: ((LiveSourceDescriptor) -> Void)? { get set }
    var onConnected: ((LiveSourceDescriptor) -> Void)? { get set }
    var onDisconnected: (() -> Void)? { get set }
    var onMeasurement: ((BluetoothHeartRateMeasurement, Date, String) -> Void)? { get set }

    func startScanning()
    func connect(identifier: String)
    func reconnect(identifier: String)
    func disconnect()
}

enum BluetoothConnectionFailureAction: Equatable {
    case ignore
    case awaitCoordinatorRetry
}

struct BluetoothReconnectPolicy {
    private(set) var desiredIdentifier: String?

    mutating func requestConnection(identifier: String) {
        desiredIdentifier = identifier
    }

    mutating func requestManualDisconnect(identifier: String?) {
        if identifier == nil || desiredIdentifier == identifier {
            desiredIdentifier = nil
        }
    }

    func shouldReconnect(identifier: String) -> Bool {
        desiredIdentifier == identifier
    }

    func connectionFailureAction(identifier: String) -> BluetoothConnectionFailureAction {
        desiredIdentifier == identifier ? .awaitCoordinatorRetry : .ignore
    }
}

final class BluetoothHeartRateSource: NSObject, BluetoothHeartRateProviding, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onDiscovery: ((LiveSourceDescriptor) -> Void)?
    var onConnected: ((LiveSourceDescriptor) -> Void)?
    var onDisconnected: (() -> Void)?
    var onMeasurement: ((BluetoothHeartRateMeasurement, Date, String) -> Void)?

    private var central: CBCentralManager?
    private var peripherals: [String: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var reconnectPolicy = BluetoothReconnectPolicy()
    private let heartRateService = CBUUID(string: "180D")
    private let heartRateMeasurement = CBUUID(string: "2A37")

    func startScanning() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "FitTune.HeartRateCentral"])
        } else if central?.state == .poweredOn {
            central?.scanForPeripherals(withServices: [heartRateService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    func connect(identifier: String) {
        guard let peripheral = peripherals[identifier] else { return }
        reconnectPolicy.requestConnection(identifier: identifier)
        central?.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        central?.connect(peripheral)
    }

    func reconnect(identifier: String) {
        reconnectPolicy.requestConnection(identifier: identifier)
        guard let peripheral = peripherals[identifier] else {
            startScanning()
            return
        }
        connectedPeripheral = peripheral
        peripheral.delegate = self
        switch peripheral.state {
        case .connected:
            central?.cancelPeripheralConnection(peripheral)
        case .connecting:
            break
        case .disconnected:
            central?.connect(peripheral)
        case .disconnecting:
            break
        @unknown default:
            startScanning()
        }
    }

    func disconnect() {
        reconnectPolicy.requestManualDisconnect(
            identifier: connectedPeripheral?.identifier.uuidString
        )
        if let connectedPeripheral { central?.cancelPeripheralConnection(connectedPeripheral) }
        connectedPeripheral = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [heartRateService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier.uuidString
        peripherals[id] = peripheral
        onDiscovery?(LiveSourceDescriptor(id: id, kind: .bluetooth, name: peripheral.name ?? "蓝牙心率设备"))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([heartRateService])
        onConnected?(LiveSourceDescriptor(id: peripheral.identifier.uuidString, kind: .bluetooth, name: peripheral.name ?? "蓝牙心率设备"))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        let identifier = peripheral.identifier.uuidString
        guard reconnectPolicy.shouldReconnect(identifier: identifier) else { return }
        onDisconnected?()
        connectedPeripheral = peripheral
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        let identifier = peripheral.identifier.uuidString
        guard reconnectPolicy.connectionFailureAction(identifier: identifier) == .awaitCoordinatorRetry else {
            return
        }
        onDisconnected?()
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in restored {
            peripherals[peripheral.identifier.uuidString] = peripheral
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        peripheral.services?.forEach { peripheral.discoverCharacteristics([heartRateMeasurement], for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        service.characteristics?.filter { $0.uuid == heartRateMeasurement }.forEach { peripheral.setNotifyValue(true, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard error == nil, let data = characteristic.value,
              let measurement = try? BluetoothHeartRateParser.parse(Array(data)) else { return }
        onMeasurement?(measurement, .now, peripheral.name ?? "蓝牙心率设备")
    }
}
