import Foundation
import IOBluetooth

/// Fit900NB's documented SPP transport. Uses SDP instead of guessing a channel for other models.
final class EdifierRFCOMMConnection: NSObject, IOBluetoothRFCOMMChannelDelegate {
    let native: IOBluetoothDevice
    let session: EdifierControlSession
    private var channel: IOBluetoothRFCOMMChannel?
    private var connecting = false
    private var deadline: TimeInterval = 0
    private var retryAfter: TimeInterval = 0
    private var failureCount = 0
    private var writeBuffer: NSMutableData?
    private var writeGate = EdifierWriteGate()
    private var writeDeadline: TimeInterval = 0
    private var enabled = true
    var isOpen: Bool { channel?.isOpen() == true }

    init(native: IOBluetoothDevice, device: HeadphoneDevice) {
        self.native = native
        session = EdifierControlSession(device: device)
        super.init()
        session.send = { [weak self] data in
            guard let self else { return false }
            guard let channel = self.channel, channel.isOpen(), self.writeBuffer == nil,
                  data.count <= Int(channel.getMTU()), data.count <= Int(UInt16.max) else {
                self.session.log("SPP writer not ready: open=\(self.isOpen), pending=\(self.writeBuffer != nil), mtu=\(self.channel?.getMTU() ?? 0), bytes=\(data.count)")
                return false
            }
            guard let token = self.writeGate.begin() else { return false }
            let buffer = NSMutableData(data: data)
            self.writeBuffer = buffer // The async API requires bytes to live through write completion.
            self.writeDeadline = ProcessInfo.processInfo.systemUptime + 3
            let result = channel.writeAsync(buffer.mutableBytes, length: UInt16(buffer.length), refcon: UnsafeMutableRawPointer(bitPattern: token))
            self.session.log("SPP writeAsync returned \(result) (\(data.count) bytes)")
            if result != kIOReturnSuccess { self.writeBuffer = nil; self.writeGate.cancel() }
            return result == kIOReturnSuccess
        }
    }

    func tick(now: TimeInterval) {
        guard enabled else { return }
        if !native.isConnected() {
            if isOpen || connecting { close() }
            return
        }
        if connecting, now > deadline { failed("Headphone control connection timed out. Reconnecting…") }
        if writeBuffer != nil, now > writeDeadline { failed("SPP write timed out. Retry headphone controls.") }
        if !isOpen, !connecting, now >= retryAfter { connect(now: now) }
        session.tick(now: now)
        if session.isReady { failureCount = 0 }
        if isOpen, session.device.controlState == .unavailable {
            failed("Headphone controls stopped responding. Reconnecting…")
        }
    }

    func retry() {
        enabled = true
        failureCount = 0
        close()
        // Let macOS and the headset finish closing the old channel before reopening its DLC.
        retryAfter = ProcessInfo.processInfo.systemUptime + 1
        session.device.controlState = .connecting
        session.onUpdate?(session.device)
    }

    func stop() { enabled = false; close() }

    private func connect(now: TimeInterval) {
        guard enabled, native.isConnected(), !connecting, !isOpen else { return }
        connecting = true
        deadline = now + 12
        session.device.controlState = .connecting
        session.device.controlError = nil
        session.onUpdate?(session.device)
        if let channelID = serviceChannel() { open(channelID); return }
        session.log("Discover Fit900NB SPP service EDF00000-EDFE-DFED-FEDF-EDFEDFEDFEDF")
        if native.performSDPQuery(self) != kIOReturnSuccess { openFallback() }
    }

    private func serviceChannel() -> BluetoothRFCOMMChannelID? {
        let bytes: [UInt8] = [0xED, 0xF0, 0, 0, 0xED, 0xFE, 0xDF, 0xED, 0xFE, 0xDF, 0xED, 0xFE, 0xDF, 0xED, 0xFE, 0xDF]
        let uuid = IOBluetoothSDPUUID(data: Data(bytes))
        guard let service = native.getServiceRecord(for: uuid) else { return nil }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess, channelID > 0 else { return nil }
        return channelID
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled, self.connecting, self.channel == nil else { return }
            if status == kIOReturnSuccess, let channelID = self.serviceChannel() { self.open(channelID) }
            else { self.openFallback() }
        }
    }

    private func openFallback() {
        // This fallback is documented for Fit900NB only, never used on an unknown Edifier.
        guard session.device.edifierProfile == .fit900NB else { failed("No supported SPP service found."); return }
        session.log("Fit900NB SPP fallback: RFCOMM channel 1")
        open(1)
    }

    private func open(_ channelID: BluetoothRFCOMMChannelID) {
        session.log("Open SPP channel \(channelID)")
        let result = native.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: self)
        if result != kIOReturnSuccess { failed("SPP open failed (\(result)). Close the phone app and retry.") }
    }

    private func close() {
        connecting = false
        let previous = channel
        channel = nil
        // Detach before close so a late callback cannot invalidate a new session.
        previous?.setDelegate(nil)
        previous?.close()
        writeBuffer = nil
        writeGate.cancel()
        session.disconnect()
    }

    private func failed(_ message: String) {
        close()
        failureCount = min(failureCount + 1, 6)
        retryAfter = ProcessInfo.processInfo.systemUptime + min(pow(2, Double(failureCount)), 60)
        session.transportFailed(message)
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled, rfcommChannel === self.channel else { return }
            self.connecting = false
            if error == kIOReturnSuccess {
                self.session.device.isConnected = true
                self.session.log("SPP channel open")
                self.session.start(now: ProcessInfo.processInfo.systemUptime)
            } else { self.failed("SPP connection failed (\(error)). Close the phone app and retry.") }
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        DispatchQueue.main.async { [weak self] in
            guard let self, rfcommChannel === self.channel else { return }
            self.session.receive(data, now: ProcessInfo.processInfo.systemUptime)
        }
    }

    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        writeCompleted(rfcommChannel, token: UInt(bitPattern: refcon), status: error)
    }

    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn, bytesWritten length: Int) {
        writeCompleted(rfcommChannel, token: UInt(bitPattern: refcon), status: error)
    }

    private func writeCompleted(_ rfcommChannel: IOBluetoothRFCOMMChannel?, token: UInt, status error: IOReturn) {
        DispatchQueue.main.async { [weak self] in
            guard let self, rfcommChannel === self.channel, self.writeGate.finish(token) else { return }
            self.session.log("SPP write completion: \(error)")
            self.writeBuffer = nil
            if error != kIOReturnSuccess { self.failed("SPP write failed (\(error)). Retry headphone controls.") }
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        DispatchQueue.main.async { [weak self] in
            guard let self, rfcommChannel === self.channel else { return }
            self.failed("Headphone control connection closed. Reconnecting…")
        }
    }
}
