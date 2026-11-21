import Foundation
import CoreBluetooth
import IOBluetooth
import Combine

public class EdifierBLEManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public static let shared = EdifierBLEManager()
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic? // Host writes to device
    private var txCharacteristic: CBCharacteristic? // Device notifies host
    
    private var pollTimer: Timer?
    private var receiveBuffer = Data()
    
    public var onDeviceUpdated: ((HeadphoneDevice) -> Void)?
    public var currentDevice: HeadphoneDevice?
    
    // Known Edifier UUID substrings
    private let edifierBaseUUIDSuffix = "-1a48-11e9-ab14-d663bd873d93"
    private let rxUUIDString = "48090002-1a48-11e9-ab14-d663bd873d93"
    private let txUUIDString = "48090001-1a48-11e9-ab14-d663bd873d93"
    
    private let targetKeywords = ["edifier", "fit900", "w820", "w200", "neobuds"]
    
    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.global(qos: .utility))
    }
    
    public func start() {
        checkPairedClassicDevices()
        if centralManager.state == .poweredOn {
            startScanning()
        }
        startPollTimer()
    }
    
    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        centralManager.stopScan()
        if let p = connectedPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
    }
    
    private func checkPairedClassicDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        for dev in paired {
            let name = (dev.name ?? "").lowercased()
            if targetKeywords.contains(where: { name.contains($0) }) {
                let devName = dev.name ?? "EDIFIER Headphone"
                let devID = dev.addressString ?? "edifier-device"
                if currentDevice == nil {
                    let model = HeadphoneDevice(
                        id: devID,
                        name: devName,
                        brand: .edifier,
                        isConnected: dev.isConnected()
                    )
                    currentDevice = model
                    DispatchQueue.main.async {
                        self.onDeviceUpdated?(model)
                    }
                }
                break
            }
        }
    }
    
    private func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }
    
    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.connectedPeripheral == nil || self.connectedPeripheral?.state != .connected {
                self.checkPairedClassicDevices()
                self.startScanning()
            } else {
                self.queryBattery()
                self.queryANCMode()
                self.queryGameMode()
            }
        }
    }
    
    // MARK: - Control Commands
    
    public func setANCMode(_ mode: ANCMode) {
        let packet = EdifierPacket.buildANCSetRequest(mode: mode)
        sendPacket(packet)
        
        if let dev = currentDevice {
            dev.ancMode = mode
            DispatchQueue.main.async {
                self.onDeviceUpdated?(dev)
            }
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            self.queryANCMode()
        }
    }
    
    public func setGameMode(enabled: Bool) {
        let packet = EdifierPacket.buildGameModeSetRequest(enabled: enabled)
        sendPacket(packet)
        
        if let dev = currentDevice {
            dev.gameModeEnabled = enabled
            DispatchQueue.main.async {
                self.onDeviceUpdated?(dev)
            }
        }
    }
    
    public func queryBattery() {
        let packet = EdifierPacket.buildBatteryRequest()
        sendPacket(packet)
    }
    
    public func queryANCMode() {
        let packet = EdifierPacket.buildANCGetRequest()
        sendPacket(packet)
    }
    
    public func queryGameMode() {
        let packet = EdifierPacket.buildGameModeGetRequest()
        sendPacket(packet)
    }
    
    private func sendPacket(_ data: Data) {
        guard let p = connectedPeripheral, let rx = rxCharacteristic else {
            return
        }
        let type: CBCharacteristicWriteType = rx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        p.writeValue(data, for: rx, type: type)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? (peripheral.name ?? "")
        let lowerName = advName.lowercased()
        
        let isMatch = targetKeywords.contains { lowerName.contains($0) }
        guard isMatch else { return }
        
        print("[Edifier] Discovered matching peripheral: \(advName)")
        self.connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
        
        DispatchQueue.main.async {
            if let dev = self.currentDevice {
                dev.name = advName
                dev.lastUpdated = Date()
                self.onDeviceUpdated?(dev)
            } else {
                let model = HeadphoneDevice(
                    id: peripheral.identifier.uuidString,
                    name: advName,
                    brand: .edifier,
                    isConnected: false
                )
                self.currentDevice = model
                self.onDeviceUpdated?(model)
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[Edifier] Connected to peripheral: \(peripheral.name ?? "")")
        DispatchQueue.main.async {
            if let dev = self.currentDevice {
                dev.isConnected = true
                dev.lastUpdated = Date()
                self.onDeviceUpdated?(dev)
            }
        }
        peripheral.discoverServices(nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[Edifier] Disconnected from peripheral: \(peripheral.name ?? "")")
        rxCharacteristic = nil
        txCharacteristic = nil
        connectedPeripheral = nil
        
        DispatchQueue.main.async {
            if let dev = self.currentDevice {
                dev.isConnected = false
                dev.lastUpdated = Date()
                self.onDeviceUpdated?(dev)
            }
        }
        
        // Restart scan to reconnect when device turns back on
        startScanning()
    }
    
    // MARK: - CBPeripheralDelegate
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            let uuid = char.uuid.uuidString.lowercased()
            
            // Check for known Edifier RX/TX or general write/notify
            if uuid == rxUUIDString.lowercased() || (char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse)) && rxCharacteristic == nil {
                rxCharacteristic = char
            }
            
            if uuid == txUUIDString.lowercased() || char.properties.contains(.notify) && txCharacteristic == nil {
                txCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
        
        if rxCharacteristic != nil && txCharacteristic != nil {
            print("[Edifier] Discovered RX and TX characteristics. Ready for commands!")
            // Query state
            queryBattery()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                self.queryANCMode()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                self.queryGameMode()
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        receiveBuffer.append(value)
        processReceiveBuffer()
    }
    
    private func processReceiveBuffer() {
        while receiveBuffer.count >= 5 {
            guard let startIdx = receiveBuffer.firstIndex(where: {
                $0 == EdifierPacket.responseInitBB || $0 == EdifierPacket.responseInitCC || $0 == EdifierPacket.requestInit
            }) else {
                receiveBuffer.removeAll()
                return
            }
            if startIdx > 0 {
                receiveBuffer.removeSubrange(0..<startIdx)
            }
            guard receiveBuffer.count >= 5 else { return }
            
            let length = Int(receiveBuffer[1])
            let fullPacketLen = length + 4
            
            guard receiveBuffer.count >= fullPacketLen else { return }
            
            let packetData = receiveBuffer.subdata(in: 0..<fullPacketLen)
            receiveBuffer.removeSubrange(0..<fullPacketLen)
            
            if let packet = EdifierPacket.fromData(packetData) {
                handleIncomingPacket(packet)
            }
        }
    }
    
    private func handleIncomingPacket(_ packet: EdifierPacket) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let dev = self.currentDevice else { return }
            
            switch packet.command {
            case EdifierPacket.cmdBatteryGet:
                if packet.data.count >= 1 {
                    dev.batteryLevel = Int(packet.data[0])
                    dev.lastUpdated = Date()
                    self.onDeviceUpdated?(dev)
                }
                
            case EdifierPacket.cmdANCGet, EdifierPacket.cmdANCSet:
                if packet.data.count >= 1 {
                    let modeByte = packet.data[0]
                    switch modeByte {
                    case 0x02:
                        dev.ancMode = .cancellation
                    case 0x03:
                        dev.ancMode = .awareness
                    default:
                        dev.ancMode = .off
                    }
                    dev.lastUpdated = Date()
                    self.onDeviceUpdated?(dev)
                }
                
            case EdifierPacket.cmdGameModeGet, EdifierPacket.cmdGameModeSet:
                if packet.data.count >= 1 {
                    dev.gameModeEnabled = (packet.data[0] == 0x01)
                    dev.lastUpdated = Date()
                    self.onDeviceUpdated?(dev)
                }
                
            case EdifierPacket.cmdDeviceNameGet:
                if let name = String(data: packet.data, encoding: .utf8), !name.isEmpty {
                    dev.name = name
                    dev.lastUpdated = Date()
                    self.onDeviceUpdated?(dev)
                }
                
            default:
                break
            }
        }
    }
}
