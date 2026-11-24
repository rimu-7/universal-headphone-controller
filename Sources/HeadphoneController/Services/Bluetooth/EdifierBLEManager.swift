import Foundation
import CoreBluetooth
import IOBluetooth

/// Discovers multiple independent control sessions and joins Classic/BLE identities only by a verified MAC.
public final class EdifierBLEManager: NSObject, CBCentralManagerDelegate {
    public static let shared = EdifierBLEManager()
    public var onDeviceUpdated: ((HeadphoneDevice) -> Void)?
    public var onDeviceRemoved: ((String) -> Void)?
    private var central: CBCentralManager!
    private var timer: Timer?
    private var running = false
    private var connections: [UUID: EdifierBLEConnection] = [:]
    private var classicConnections: [String: EdifierRFCOMMConnection] = [:]
    private var devices: [String: HeadphoneDevice] = [:]
    private var audioConnected: Set<String> = []
    private var retryAfter: [UUID: TimeInterval] = [:]
    private var failures: [UUID: Int] = [:]
    private var nextDiscovery: TimeInterval = 0
    private var nextClassicPoll: TimeInterval = 0
    private var nextBatteryPoll: TimeInterval = 0
    private var batteryPollInProgress = false
    private var pairedPollInProgress = false
    private var pairedPollGeneration = 0
    private var identities = UserDefaults.standard.dictionary(forKey: "edifier.verifiedIdentities") as? [String: String] ?? [:]
    private var serviceUUIDs = Set(EdifierProfile.knownServices)
        .union(UserDefaults.standard.stringArray(forKey: "edifier.serviceUUIDs") ?? [])

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    public func start() {
        guard !running else { return }
        running = true
        nextBatteryPoll = 0
        checkPairedClassicDevices()
        for connection in classicConnections.values { connection.retry() }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        discover()
    }

    public func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        central.stopScan()
        for connection in classicConnections.values { connection.stop() }
        for connection in connections.values {
            connection.session.disconnect()
            central.cancelPeripheralConnection(connection.peripheral)
        }
    }

    public func refresh() {
        nextBatteryPoll = 0
        checkPairedClassicDevices()
        for connection in classicConnections.values where connection.session.device.controlState == .ready {
            connection.session.device.controlError = nil
            connection.session.refresh(includeMetadata: true)
        }
        for connection in connections.values where connection.session.device.controlState == .ready {
            connection.session.device.controlError = nil
            connection.session.refresh(includeMetadata: true)
        }
        discover()
    }

    public func retry(deviceID: String) {
        nextBatteryPoll = 0
        checkPairedClassicDevices()
        if let classic = classicConnections[deviceID] { classic.retry(); return }
        for connection in connections.values where connection.session.device.id == deviceID {
            retryAfter[connection.peripheral.identifier] = nil
            if connection.peripheral.state == .connected {
                connection.retry()
            } else {
                connect(connection.peripheral)
            }
        }
        discover()
    }

    public func setANCMode(for id: String, mode: ANCMode, ambientLevel: UInt8? = nil) {
        session(for: id)?.setANC(mode, level: ambientLevel)
    }

    public func setGameMode(for id: String, enabled: Bool) { session(for: id)?.setGameMode(enabled) }
    public func setEqualizer(for id: String, preset: EqualizerPreset) { session(for: id)?.setEqualizer(preset) }
    public func setNoiseOption(for id: String, value: UInt8, level: UInt8? = nil) { session(for: id)?.setNoiseOption(value, level: level) }
    public func setScene(for id: String, scene: EdifierScene) { session(for: id)?.setScene(scene) }

    public func diagnosticReport(for id: String) -> String {
        guard let device = devices[id] else { return "No device information available." }
        let connection = connections.values.first { $0.session.device.id == id }
        let session = classicConnections[id]?.session ?? connection?.session
        let lines = ["Headphone Controller — Edifier diagnostics", "Model: \(device.name)",
                     "Profile: \(device.edifierProfile.rawValue)", "Controls: \(device.controlState.rawValue)",
                     "Transport: \(device.edifierProfile == .fit900NB ? "Classic SPP/RFCOMM" : "BLE GATT")",
                     "Framing: \(session?.framing?.rawValue ?? "not detected")",
                     "Firmware: \(device.firmwareVersion ?? "unknown")",
                     "Confirmed features: \(device.supportedFeatures.map(\.rawValue).sorted().joined(separator: ", "))",
                     "Error: \(device.controlError ?? "none")"]
        return (lines + (session?.diagnostics ?? [])).joined(separator: "\n")
    }

    private func session(for id: String) -> EdifierControlSession? {
        if let session = classicConnections[id]?.session, session.isReady { return session }
        return connections.values.first { $0.session.device.id == id && $0.session.isReady }?.session
    }

    private func tick() {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextClassicPoll { checkPairedClassicDevices(); nextClassicPoll = now + 3 }
        if now >= nextBatteryPoll, !batteryPollInProgress {
            nextBatteryPoll = now + 60
            batteryPollInProgress = true
            BluetoothBatteryReader.fetchDevices { [weak self] snapshot in
                guard let self else { return }
                self.batteryPollInProgress = false
                guard self.running, let snapshot else { return }
                self.updateSystemDevices(snapshot)
            }
        }
        for connection in classicConnections.values { connection.tick(now: now) }
        for connection in Array(connections.values) {
            connection.tick(now: now)
            if let started = connection.connectStarted, now - started > 15 {
                connection.connectStarted = nil
                connection.session.transportFailed("Bluetooth connection timed out. Retry the connection.")
                central.cancelPeripheralConnection(connection.peripheral)
            }
        }
        if now >= nextDiscovery {
            discover()
            nextDiscovery = now + 15
        }
    }

    public func checkPairedClassicDevices() {
        guard !pairedPollInProgress else { return }
        pairedPollInProgress = true
        pairedPollGeneration += 1
        let generation = pairedPollGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.running, self.pairedPollInProgress, self.pairedPollGeneration == generation else { return }
            for device in self.devices.values where device.controlState == .searching {
                device.controlState = .unavailable
                device.controlError = "macOS Bluetooth access is not responding. Check Bluetooth permission, then relaunch the app."
                self.onDeviceUpdated?(device)
            }
        }
        PairedBluetoothDeviceReader.fetch { [weak self] paired in
            guard let self else { return }
            self.pairedPollInProgress = false
            guard self.running else { return }
            self.updateClassicDevices(paired)
        }
    }

    private func updateSystemDevices(_ snapshot: [SystemBluetoothDevice]) {
        let edifier = snapshot.filter { EdifierProfile.matches(name: $0.name) && $0.name.lowercased() != "edifier ble" }
        audioConnected = Set(edifier.filter(\.isConnected).map { Self.classicID($0.address) })
        for record in edifier {
            let id = Self.classicID(record.address)
            let device = devices[id] ?? HeadphoneDevice(id: id, name: record.name, brand: .edifier)
            devices[id] = device
            device.name = record.name
            if device.edifierProfile == .unknown { device.edifierProfile = EdifierProfile.resolve(name: record.name) }
            if device.edifierProfile == .fit900NB { retireBLEConnections(for: id) }
            if let battery = record.battery, !device.batteryIsFromControl || device.controlState != .ready {
                device.batteryLevel = battery
            }
            if record.isConnected, device.controlState == .disconnected { device.controlState = bluetoothState }
        }
        for device in devices.values {
            let controlConnected = classicConnections[device.id]?.isOpen == true || connections.values.contains {
                $0.session.device.id == device.id && $0.peripheral.state == .connected
            }
            device.isConnected = audioConnected.contains(device.id) || controlConnected
            onDeviceUpdated?(device)
        }
    }

    private func updateClassicDevices(_ paired: [IOBluetoothDevice]) {
        audioConnected.removeAll()
        for native in paired {
            guard let name = native.name, EdifierProfile.matches(name: name),
                  name.lowercased() != "edifier ble", let address = native.addressString else { continue }
            let id = Self.classicID(address)
            let device = devices[id] ?? HeadphoneDevice(id: id, name: name, brand: .edifier)
            devices[id] = device
            device.name = name
            if device.edifierProfile == .unknown { device.edifierProfile = EdifierProfile.resolve(name: name) }
            if device.edifierProfile == .fit900NB { retireBLEConnections(for: id) }
            if device.edifierProfile == .fit900NB, classicConnections[id] == nil {
                let connection = EdifierRFCOMMConnection(native: native, device: device)
                connection.session.onUpdate = { [weak self] device in self?.onDeviceUpdated?(device) }
                classicConnections[id] = connection
            }
            if native.isConnected() {
                audioConnected.insert(id)
                if device.controlState == .disconnected { device.controlState = bluetoothState }
            }
        }
        // Recompute every row, including devices that disappeared from pairedDevices().
        for device in devices.values {
            let controlConnected = classicConnections[device.id]?.isOpen == true || connections.values.contains {
                $0.session.device.id == device.id && $0.peripheral.state == .connected
            }
            device.isConnected = audioConnected.contains(device.id) || controlConnected
            if !device.isConnected, device.controlState == .ready { device.controlState = .disconnected }
            onDeviceUpdated?(device)
        }
    }

    private var bluetoothState: HeadphoneControlState {
        switch central.state {
        case .unauthorized: return .permissionDenied
        case .poweredOff, .unsupported: return .bluetoothOff
        default: return .searching
        }
    }

    private func retireBLEConnections(for id: String) {
        let losing = connections.filter { $0.value.session.device.id == id || identities[$0.key.uuidString] == id }
        for (identifier, connection) in losing {
            connections.removeValue(forKey: identifier)
            connection.session.retire()
            connection.clear()
            connection.peripheral.delegate = nil
            central.cancelPeripheralConnection(connection.peripheral)
        }
    }

    private func discover() {
        guard running, central.state == .poweredOn else { return }
        // macOS-held peripherals often no longer advertise. Scanning alone misses them.
        let services = serviceUUIDs.map(CBUUID.init(string:))
        let held = central.retrieveConnectedPeripherals(withServices: services)
        let cachedIDs = identities.keys.compactMap(UUID.init(uuidString:))
        let cached = central.retrievePeripherals(withIdentifiers: cachedIDs)
        for peripheral in held + cached { connect(peripheral) }
        if !central.isScanning { central.scanForPeripherals(withServices: nil, options: nil) }
        // Bound each broad scan; retries also recover after sleep and Bluetooth toggles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.central.stopScan() }
    }

    private func connect(_ peripheral: CBPeripheral) {
        guard running, central.state == .poweredOn else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard peripheral.state != .disconnecting else { return }
        let knownID = identities[peripheral.identifier.uuidString]
        if EdifierProfile.resolve(name: peripheral.name ?? "") == .fit900NB ||
            knownID.flatMap({ devices[$0]?.edifierProfile }) == .fit900NB ||
            knownID.flatMap({ classicConnections[$0] }) != nil { return }
        guard now >= (retryAfter[peripheral.identifier] ?? 0) else { return }
        if let existing = connections[peripheral.identifier], existing.connectStarted != nil || existing.isActive { return }
        // Keep sessions independent; a nearby Edifier must never replace another device's model.
        let connection: EdifierBLEConnection
        if let existing = connections[peripheral.identifier] {
            connection = existing
        } else {
            guard connections.count < 16 else { return }
            let id = identities[peripheral.identifier.uuidString] ?? "edifier-ble-\(peripheral.identifier.uuidString)"
            let device = devices[id] ?? HeadphoneDevice(id: id, name: peripheral.name ?? "Edifier headphones", brand: .edifier)
            device.edifierProfile = EdifierProfile.resolve(name: device.name)
            devices[id] = device
            connection = EdifierBLEConnection(peripheral: peripheral, device: device)
            connections[peripheral.identifier] = connection
            connection.session.onUpdate = { [weak self] device in self?.onDeviceUpdated?(device) }
            connection.session.onIdentity = { [weak self, weak connection] address in
                guard let self, let connection else { return }
                self.bindIdentity(address, connection: connection)
            }
            connection.onService = { [weak self] uuid in
                guard let self else { return }
                self.serviceUUIDs.insert(uuid)
                UserDefaults.standard.set(Array(self.serviceUUIDs), forKey: "edifier.serviceUUIDs")
            }
        }
        connection.session.device.controlState = .connecting
        connection.connectStarted = now
        onDeviceUpdated?(connection.session.device)
        peripheral.delegate = connection
        central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    private func bindIdentity(_ address: String, connection: EdifierBLEConnection) {
        let id = Self.classicID(address)
        let old = connection.session.device
        identities[connection.peripheral.identifier.uuidString] = id
        UserDefaults.standard.set(identities, forKey: "edifier.verifiedIdentities")
        if classicConnections[id] != nil, old.id != id {
            // Prefer Fit900NB's SPP channel; never let a second transport reset its confirmed state.
            connection.session.retire()
            connections.removeValue(forKey: connection.peripheral.identifier)
            devices.removeValue(forKey: old.id)
            central.cancelPeripheralConnection(connection.peripheral)
            onDeviceRemoved?(old.id)
            return
        }
        guard old.id != id else { return }
        let device = devices[id] ?? HeadphoneDevice(id: id, name: old.name, brand: .edifier)
        device.batteryLevel = old.batteryLevel ?? device.batteryLevel
        device.batteryIsFromControl = old.batteryIsFromControl
        device.controlState = old.controlState
        device.supportedFeatures = old.supportedFeatures
        device.pendingFeatures = old.pendingFeatures
        device.hasANCState = old.hasANCState
        device.ancMode = old.ancMode
        device.ancLevel = old.ancLevel
        device.gameModeEnabled = old.gameModeEnabled
        device.equalizerPreset = old.equalizerPreset
        device.firmwareVersion = old.firmwareVersion
        device.controlError = old.controlError
        device.edifierANCIndex = old.edifierANCIndex
        device.edifierNoiseValue = old.edifierNoiseValue
        device.edifierScene = old.edifierScene
        device.edifierCancellationSelection = old.edifierCancellationSelection ?? device.edifierCancellationSelection
        device.isConnected = true
        if device.edifierProfile == .unknown { device.edifierProfile = old.edifierProfile }
        connection.session.device = device
        devices[id] = device
        devices.removeValue(forKey: old.id)
        onDeviceRemoved?(old.id)
        onDeviceUpdated?(device)
    }

    private static func classicID(_ address: String) -> String {
        "edifier-" + address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard running else { return }
        if central.state == .poweredOn {
            retryAfter.removeAll()
            checkPairedClassicDevices()
            for connection in classicConnections.values where [.bluetoothOff, .permissionDenied].contains(connection.session.device.controlState) {
                connection.retry()
            }
            discover()
        } else {
            central.stopScan()
            for connection in connections.values {
                connection.clear()
                connection.session.disconnect(state: bluetoothState)
            }
            for device in devices.values { device.controlState = bluetoothState; onDeviceUpdated?(device) }
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard EdifierProfile.matches(name: name) || services.contains(where: { EdifierProfile.isControlService($0.uuidString) }) else { return }
        for service in services where EdifierProfile.isControlService(service.uuidString) { serviceUUIDs.insert(service.uuidString) }
        connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        failures[peripheral.identifier] = nil
        connections[peripheral.identifier]?.connected()
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        disconnected(peripheral, error: error)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        disconnected(peripheral, error: error)
    }

    private func disconnected(_ peripheral: CBPeripheral, error: Error?) {
        guard let connection = connections[peripheral.identifier] else { return }
        connection.clear()
        connection.session.disconnect(state: running ? bluetoothState : .disconnected)
        if let error { connection.session.log("Disconnected: \(error.localizedDescription)") }
        let count = min((failures[peripheral.identifier] ?? 0) + 1, 6)
        failures[peripheral.identifier] = count
        retryAfter[peripheral.identifier] = ProcessInfo.processInfo.systemUptime + min(pow(2, Double(count)), 60)
        connection.session.device.isConnected = audioConnected.contains(connection.session.device.id)
        onDeviceUpdated?(connection.session.device)
    }
}

/// A GATT endpoint pair and writer belong to exactly one peripheral and one control service.
private final class EdifierBLEConnection: NSObject, CBPeripheralDelegate {
    let peripheral: CBPeripheral
    let session: EdifierControlSession
    var onService: ((String) -> Void)?
    var connectStarted: TimeInterval?
    var isActive: Bool { peripheral.state == .connected && rx != nil }
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var battery: CBCharacteristic?
    private var chunks: [Data] = []
    private var awaitingWrite = false
    private var writeDeadline: TimeInterval = 0
    private var nextWrite: TimeInterval = 0
    private var discoveryDeadline: TimeInterval?
    private var nextBatteryRead: TimeInterval = 0
    private var started = false

    init(peripheral: CBPeripheral, device: HeadphoneDevice) {
        self.peripheral = peripheral
        session = EdifierControlSession(device: device)
        super.init()
        session.send = { [weak self] data in
            guard let self, let rx = self.rx, self.tx?.isNotifying == true,
                  self.peripheral.state == .connected, !data.isEmpty, self.chunks.count < 64 else { return false }
            let type: CBCharacteristicWriteType = rx.properties.contains(.write) ? .withResponse : .withoutResponse
            let size = min(20, self.peripheral.maximumWriteValueLength(for: type))
            guard size > 0 else { return false }
            var offset = 0
            while offset < data.count {
                let end = min(offset + size, data.count)
                self.chunks.append(data.subdata(in: offset..<end))
                offset = end
            }
            return true
        }
    }

    func connected() {
        connectStarted = nil
        clear()
        session.device.isConnected = true
        session.device.controlState = .discovering
        discoveryDeadline = ProcessInfo.processInfo.systemUptime + 10
        session.onUpdate?(session.device)
        peripheral.discoverServices(nil)
    }

    func clear() {
        connectStarted = nil
        rx = nil; tx = nil; battery = nil
        chunks.removeAll()
        awaitingWrite = false
        started = false
        discoveryDeadline = nil
    }

    func retry() {
        chunks.removeAll()
        awaitingWrite = false
        started = false
        if rx != nil, tx?.isNotifying == true { readyIfPossible() }
        else { connected() }
    }

    func tick(now: TimeInterval) {
        if let discoveryDeadline, now > discoveryDeadline {
            self.discoveryDeadline = nil
            session.transportFailed("No compatible control channel responded. Close the phone app and retry.")
        }
        if awaitingWrite, now > writeDeadline {
            awaitingWrite = false
            chunks.removeAll()
            session.transportFailed("Bluetooth stopped acknowledging writes. Retry the connection.")
        }
        if !chunks.isEmpty, !awaitingWrite, now >= nextWrite, let rx, peripheral.state == .connected {
            let type: CBCharacteristicWriteType = rx.properties.contains(.write) ? .withResponse : .withoutResponse
            if type == .withResponse || peripheral.canSendWriteWithoutResponse {
                let chunk = chunks.removeFirst()
                awaitingWrite = type == .withResponse
                writeDeadline = now + 3
                nextWrite = now + 0.05
                peripheral.writeValue(chunk, for: rx, type: type)
            }
        }
        if now >= nextBatteryRead, let battery, battery.properties.contains(.read), peripheral.state == .connected {
            peripheral.readValue(for: battery)
            nextBatteryRead = now + 30
        }
        session.tick(now: now)
    }

    private func readyIfPossible() {
        guard !started, rx != nil, tx?.isNotifying == true else { return }
        started = true
        discoveryDeadline = nil
        session.start(now: ProcessInfo.processInfo.systemUptime)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { session.transportFailed("Service discovery failed: \(error.localizedDescription)"); return }
        for service in peripheral.services ?? [] {
            let uuid = service.uuid.uuidString
            session.log("Service \(uuid)")
            if EdifierProfile.isControlService(uuid) || service.uuid == CBUUID(string: "180F") {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        if service.uuid == CBUUID(string: "180F") {
            if let characteristic = characteristics.first(where: { $0.uuid == CBUUID(string: "2A19") }) {
                battery = characteristic
                if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
                if characteristic.properties.contains(.notify) { peripheral.setNotifyValue(true, for: characteristic) }
            }
            return
        }
        guard EdifierProfile.isControlService(service.uuid.uuidString), rx == nil else { return }
        onService?(service.uuid.uuidString)
        let profile = EdifierProfile.resolve(name: session.device.name, service: service.uuid.uuidString)
        if profile != .unknown { session.device.edifierProfile = profile }
        let writers = characteristics.filter { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
        let notifiers = characteristics.filter { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
        for characteristic in characteristics {
            session.log("Characteristic \(characteristic.uuid.uuidString) properties=\(characteristic.properties.rawValue)")
        }
        let write = writers.first { $0.uuid.uuidString.uppercased().hasPrefix("48090002-") }
            ?? writers.first { $0.uuid.uuidString.split(separator: "-").first?.hasSuffix("3") == true }
            ?? (writers.count == 1 ? writers.first : nil)
        let notify = notifiers.first { $0.uuid.uuidString.uppercased().hasPrefix("48090001-") }
            ?? notifiers.first { $0.uuid.uuidString.split(separator: "-").first?.hasSuffix("2") == true }
            ?? (notifiers.count == 1 ? notifiers.first : nil)
        guard let write, let notify else { return }
        rx = write; tx = notify
        if notify.isNotifying { readyIfPossible() }
        else { peripheral.setNotifyValue(true, for: notify) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic === tx else { return }
        if let error { session.transportFailed("Could not subscribe to headphone controls: \(error.localizedDescription)") }
        else if characteristic.isNotifying { readyIfPossible() }
        else { started = false; session.transportFailed("Headphone control notifications stopped. Retry the connection.") }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic === rx else { return }
        awaitingWrite = false
        if let error {
            chunks.removeAll()
            session.transportFailed("Bluetooth write failed: \(error.localizedDescription)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if characteristic === battery {
            guard data.count == 1, let level = data.first, level <= 100 else { return }
            session.device.batteryLevel = Int(level)
            session.device.batteryIsFromControl = true
            session.device.lastUpdated = Date()
            session.onUpdate?(session.device)
        } else if characteristic === tx {
            session.receive(data, now: ProcessInfo.processInfo.systemUptime)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        session.disconnect(state: .discovering)
        connected()
    }
}
