import Foundation
import IOBluetooth
import Combine

public class HuaweiRFCOMMManager: NSObject, IOBluetoothRFCOMMChannelDelegate {
    public static let shared = HuaweiRFCOMMManager()
    
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    private var targetDevice: IOBluetoothDevice?
    private var isConnecting = false
    private var pollTimer: Timer?
    private var receiveBuffer = Data()
    private var pairedScanInProgress = false
    private var running = false
    
    public var onDeviceUpdated: ((HeadphoneDevice) -> Void)?
    public var currentDevice: HeadphoneDevice?
    
    private let targetKeywords = ["freelace", "freebuds", "huawei"]
    
    public override init() {
        super.init()
    }
    
    public func start() {
        running = true
        scanAndConnect()
        startPollTimer()
    }
    
    public func stop() {
        running = false
        pollTimer?.invalidate()
        pollTimer = nil
        closeChannel()
    }
    
    public func scanAndConnect() {
        guard rfcommChannel == nil || !rfcommChannel!.isOpen() else { return }
        guard !isConnecting else { return }
        
        guard !pairedScanInProgress else { return }
        pairedScanInProgress = true
        PairedBluetoothDeviceReader.fetch { [weak self] pairedDevices in
            guard let self else { return }
            self.pairedScanInProgress = false
            guard self.running, !self.isConnecting, self.rfcommChannel?.isOpen() != true else { return }
            self.connectPairedDevice(pairedDevices)
        }
    }

    private func connectPairedDevice(_ pairedDevices: [IOBluetoothDevice]) {
        let huaweiDevice = pairedDevices.first { device in
            let name = (device.name ?? "").lowercased()
            return targetKeywords.contains { name.contains($0) }
        }
        
        guard let device = huaweiDevice else {
            return
        }
        
        let deviceName = device.name ?? "HUAWEI FreeLace"
        let deviceID = device.addressString ?? "huawei-freelace"
        
        if currentDevice == nil {
            let model = HeadphoneDevice(
                id: deviceID,
                name: deviceName,
                brand: .huawei,
                isConnected: false,
                equalizerPreset: .defaultPreset
            )
            currentDevice = model
            onDeviceUpdated?(model)
        }
        
        guard device.isConnected() else {
            if let dev = currentDevice, dev.isConnected {
                dev.isConnected = false
                onDeviceUpdated?(dev)
            }
            return
        }
        
        connectToDevice(device)
    }
    
    private func connectToDevice(_ device: IOBluetoothDevice) {
        self.targetDevice = device
        self.isConnecting = true
        
        // Open RFCOMM channel on port 1
        let status = device.openRFCOMMChannelAsync(&rfcommChannel, withChannelID: 1, delegate: self)
        if status != kIOReturnSuccess {
            self.isConnecting = false
            print("[Huawei] Failed to initiate RFCOMM open: \(status)")
        }
    }
    
    public func setANCMode(_ mode: ANCMode) {
        guard let channel = rfcommChannel, channel.isOpen() else {
            print("[Huawei] Cannot set ANC: Channel not open")
            return
        }
        let packet = HuaweiPacket.buildANCWriteRequest(mode: mode)
        sendData(packet)
        
        if let dev = currentDevice {
            dev.ancMode = mode
            onDeviceUpdated?(dev)
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            self.queryANCMode()
        }
    }
    
    public func setEqualizer(_ preset: EqualizerPreset) {
        guard let channel = rfcommChannel, channel.isOpen() else {
            print("[Huawei] Cannot set EQ: Channel not open")
            return
        }
        print("[Huawei] Setting EQ Preset to \(preset.title) (mode \(preset.rawValue)) via CMD 2B49")
        let packet = HuaweiPacket.buildEqualizerWriteRequest(preset: preset)
        sendData(packet)
        
        if let dev = currentDevice {
            dev.equalizerPreset = preset
            onDeviceUpdated?(dev)
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.queryEqualizer()
        }
    }
    
    public func setLowLatency(enabled: Bool) {
        guard let channel = rfcommChannel, channel.isOpen() else { return }
        let packet = HuaweiPacket.buildLowLatencyRequest(enabled: enabled)
        sendData(packet)
        if let dev = currentDevice {
            dev.gameModeEnabled = enabled
            onDeviceUpdated?(dev)
        }
    }
    
    public func queryBattery() {
        guard let channel = rfcommChannel, channel.isOpen() else { return }
        sendData(HuaweiPacket.buildBatteryReadRequest())
    }
    
    public func queryANCMode() {
        guard let channel = rfcommChannel, channel.isOpen() else { return }
        sendData(HuaweiPacket.buildANCReadRequest())
    }
    
    public func queryEqualizer() {
        guard let channel = rfcommChannel, channel.isOpen() else { return }
        sendData(HuaweiPacket.buildEqualizerReadRequest())
    }
    
    private func sendData(_ data: Data) {
        guard let channel = rfcommChannel, channel.isOpen() else { return }
        var mutableData = data
        mutableData.withUnsafeMutableBytes { ptr in
            _ = channel.writeAsync(ptr.baseAddress, length: UInt16(data.count), refcon: nil)
        }
    }
    
    private func closeChannel() {
        rfcommChannel?.close()
        rfcommChannel = nil
        isConnecting = false
        if let dev = currentDevice {
            dev.isConnected = false
            onDeviceUpdated?(dev)
        }
    }
    
    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.rfcommChannel == nil || !self.rfcommChannel!.isOpen() {
                self.scanAndConnect()
            } else {
                self.queryBattery()
                self.queryANCMode()
                self.queryEqualizer()
            }
        }
    }
    
    // MARK: - IOBluetoothRFCOMMChannelDelegate
    
    @objc public func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        isConnecting = false
        if status == kIOReturnSuccess {
            self.rfcommChannel = channel
            print("[Huawei] RFCOMM channel connected successfully.")
            
            DispatchQueue.main.async {
                if let dev = self.currentDevice {
                    dev.isConnected = true
                    self.onDeviceUpdated?(dev)
                }
            }
            
            // Query initial state: battery, ANC mode, and EQ
            queryBattery()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                self.queryANCMode()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                self.queryEqualizer()
            }
        } else {
            print("[Huawei] RFCOMM open failed with status: \(status)")
            closeChannel()
        }
    }
    
    @objc public func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        let chunk = Data(bytes: pointer, count: length)
        receiveBuffer.append(chunk)
        processReceiveBuffer()
    }
    
    @objc public func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        print("[Huawei] RFCOMM channel closed.")
        closeChannel()
    }
    
    // MARK: - Packet Processing
    
    private func processReceiveBuffer() {
        while receiveBuffer.count >= 6 {
            guard let startIdx = receiveBuffer.firstIndex(of: HuaweiPacket.magicByte) else {
                receiveBuffer.removeAll()
                return
            }
            if startIdx > 0 {
                receiveBuffer.removeSubrange(0..<startIdx)
            }
            guard receiveBuffer.count >= 6 else { return }
            
            let totalLength = (Int(receiveBuffer[1]) << 8) | Int(receiveBuffer[2])
            let fullPacketLen = totalLength + 3 + 2
            
            guard receiveBuffer.count >= fullPacketLen else { return }
            
            let packetData = receiveBuffer.subdata(in: 0..<fullPacketLen)
            receiveBuffer.removeSubrange(0..<fullPacketLen)
            
            if let packet = HuaweiPacket.fromData(packetData) {
                handleIncomingPacket(packet)
            }
        }
    }
    
    private func handleIncomingPacket(_ packet: HuaweiPacket) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let dev = self.currentDevice else { return }
            
            switch packet.command {
            case HuaweiPacket.cmdBatteryRead, HuaweiPacket.cmdBatteryNotify:
                if let p1 = packet.parameters[1], p1.count >= 1 {
                    dev.batteryLevel = Int(p1[0])
                }
                if let p3 = packet.parameters[3], p3.count >= 1 {
                    dev.isCharging = (p3[0] == 0x01)
                }
                dev.lastUpdated = Date()
                self.onDeviceUpdated?(dev)
                
            case HuaweiPacket.cmdANCRead:
                if let p1 = packet.parameters[1], p1.count >= 2 {
                    let level = Int(p1[0])
                    let modeRaw = Int(p1[1])
                    dev.ancLevel = level
                    switch modeRaw {
                    case 1:
                        dev.ancMode = .cancellation
                    case 2:
                        dev.ancMode = .awareness
                    default:
                        dev.ancMode = .off
                    }
                    dev.lastUpdated = Date()
                    self.onDeviceUpdated?(dev)
                }
                
            case HuaweiPacket.cmdEqualizerRead:
                if let p2 = packet.parameters[2], p2.count >= 1 {
                    let rawVal = Int(p2[0])
                    if let preset = EqualizerPreset(rawValue: rawVal) {
                        dev.equalizerPreset = preset
                    } else if rawVal == 1 {
                        dev.equalizerPreset = .defaultPreset
                    }
                    dev.lastUpdated = Date()
                    self.onDeviceUpdated?(dev)
                }
                
            case HuaweiPacket.cmdLowLatency:
                if let p1 = packet.parameters[1], p1.count >= 1 {
                    dev.gameModeEnabled = (p1[0] == 0x01)
                    self.onDeviceUpdated?(dev)
                }
                
            default:
                break
            }
        }
    }
}
