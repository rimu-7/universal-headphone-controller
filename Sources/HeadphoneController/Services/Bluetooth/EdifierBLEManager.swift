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
    
    // Known Edifier BLE Service & Characteristic UUID substrings
    private let edifierBaseUUIDSuffix = "-1a48-11e9-ab14-d663bd873d93"
    private let rxUUIDSubstring = "48090002"
    private let txUUIDSubstring = "48090001"
    
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
    
    // MARK: - Native Classic Bluetooth & Battery Discovery
    
    public func checkPairedClassicDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        for dev in paired {
            let name = (dev.name ?? "").lowercased()
            if targetKeywords.contains(where: { name.contains($0) }) {
                let devName = dev.name ?? "EDIFIER Fit900NB"
                let devID = dev.addressString ?? "edifier-device"
                let isConnected = dev.isConnected()
                
                // Read native battery percentage via IOBluetoothDevice HFP
                let nativeBattery = readNativeBatteryLevel(from: dev)
                
                DispatchQueue.main.async {
                    if let existing = self.currentDevice {
                        existing.isConnected = isConnected
                        if let batt = nativeBattery {
                            existing.batteryLevel = batt
                        }
                        existing.lastUpdated = Date()
                        self.onDeviceUpdated?(existing)
                    } else {
                        let model = HeadphoneDevice(
                            id: devID,
                            name: devName,
                            brand: .edifier,
                            isConnected: isConnected,
                            batteryLevel: nativeBattery,
                            equalizerPreset: .defaultPreset
                        )
                        self.currentDevice = model
                        self.onDeviceUpdated?(model)
                    }
                }
                break
            }
        }
    }
    
    private func readNativeBatteryLevel(from dev: IOBluetoothDevice) -> Int? {
        typealias GetByteFunc = @convention(c) (AnyObject, Selector) -> UInt8
        let selectors = ["batteryPercentSingle", "batteryPercentCombined", "headsetBattery", "batteryPercentLeft"]
        for s in selectors {
            let sel = NSSelectorFromString(s)
            if dev.responds(to: sel) {
                let imp = dev.method(for: sel)
                let callable = unsafeBitCast(imp, to: GetByteFunc.self)
                let pct = callable(dev, sel)
                if pct > 0 && pct <= 100 {
                    return Int(pct)
                }
            }
        }
        return nil
    }
    
    private func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }
    
    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.checkPairedClassicDevices()
            
            if self.connectedPeripheral == nil || self.connectedPeripheral?.state != .connected {
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
    
    public func setEqualizer(_ preset: EqualizerPreset) {
        let effectByte: UInt8
        switch preset {
        case .defaultPreset:
            effectByte = 0x00 // Classic / Normal
        case .voices:
            effectByte = 0x01 // Pop / Vocal
        case .treble:
            effectByte = 0x02 // Classical / Treble
        case .bass:
            effectByte = 0x03 // Rock / Bass
        }
        let packet = EdifierPacket.buildSoundEffectRequest(effect: effectByte)
        sendPacket(packet)
        
        if let dev = currentDevice {
            dev.equalizerPreset = preset
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
    
    // MARK: - Multi-Transport Packet Transmission (BLE + Serial RFCOMM)
    
    private func sendPacket(_ data: Data) {
        // Transport 1: CoreBluetooth BLE
        if let p = connectedPeripheral, let rx = rxCharacteristic {
            p.writeValue(data, for: rx, type: .withResponse)
            if rx.properties.contains(.writeWithoutResponse) {
                p.writeValue(data, for: rx, type: .withoutResponse)
            }
        }
        
        // Transport 2: Classic Bluetooth Serial Port (/dev/cu.*)
        sendViaSerialPort(data)
    }
    
    private func sendViaSerialPort(_ data: Data) {
        let fileManager = FileManager.default
        let devDir = "/dev"
        guard let files = try? fileManager.contentsOfDirectory(atPath: devDir) else { return }
        
        // Match ports like /dev/cu.EDIFIERFit900NB or /dev/cu.*Fit900* or /dev/cu.*EDIFIER*
        let matchingPorts = files.filter { name in
            let lower = name.lowercased()
            return lower.hasPrefix("cu.") && (lower.contains("edifier") || lower.contains("fit900"))
        }
        
        for portName in matchingPorts {
            let fullPath = "\(devDir)/\(portName)"
            let fd = open(fullPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
            if fd >= 0 {
                data.withUnsafeBytes { ptr in
                    if let base = ptr.baseAddress {
                        _ = Darwin.write(fd, base, data.count)
                    }
                }
                close(fd)
            }
        }
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
        
        print("[Edifier] Discovered matching peripheral: \(advName) [\(peripheral.identifier)]")
        self.connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        
        DispatchQueue.main.async {
            if let dev = self.currentDevice {
                // Keep the real product name, e.g. "EDIFIER Fit900NB", don't overwrite with "EDIFIER BLE"
                if !advName.lowercased().contains("ble") {
                    dev.name = advName
                }
                dev.lastUpdated = Date()
                self.onDeviceUpdated?(dev)
            } else {
                let model = HeadphoneDevice(
                    id: peripheral.identifier.uuidString,
                    name: advName.lowercased().contains("ble") ? "EDIFIER Fit900NB" : advName,
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
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[Edifier] Failed to connect: \(String(describing: error))")
        startScanning()
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[Edifier] Disconnected from peripheral: \(peripheral.name ?? "")")
        rxCharacteristic = nil
        txCharacteristic = nil
        connectedPeripheral = nil
        
        // Refresh classic state: do NOT force disconnected if Classic BT is still active!
        checkPairedClassicDevices()
        
        // Restart scan to reconnect BLE when ready
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
            if uuid.contains(rxUUIDSubstring) || ((char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse)) && rxCharacteristic == nil) {
                rxCharacteristic = char
                print("[Edifier] Write Characteristic registered: \(char.uuid.uuidString)")
            }
            
            if uuid.contains(txUUIDSubstring) || (char.properties.contains(.notify) && txCharacteristic == nil) {
                txCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                print("[Edifier] Notify Characteristic registered: \(char.uuid.uuidString)")
            }
        }
        
        if rxCharacteristic != nil && txCharacteristic != nil {
            print("[Edifier] Ready for commands! Querying initial state...")
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
                if let name = String(data: packet.data, encoding: .utf8), !name.isEmpty, !name.lowercased().contains("ble") {
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
