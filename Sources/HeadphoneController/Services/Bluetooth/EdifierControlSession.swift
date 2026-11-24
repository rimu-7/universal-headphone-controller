import Foundation

/// Transport-independent state machine. All entry points run on the main queue.
/// A monotonic clock and injected writer keep protocol behaviour testable without Bluetooth hardware.
final class EdifierControlSession {
    struct Request {
        let command: UInt8
        var payload = Data()
        var framing: EdifierFraming?
        var feature: EdifierFeature?
        var confirmation = false
        var delay: TimeInterval = 0.15
        var isWrite: Bool { [UInt8(0xC1), 0xC4, 0x09].contains(command) }
    }

    var device: HeadphoneDevice
    var send: ((Data) -> Bool)?
    var onUpdate: ((HeadphoneDevice) -> Void)?
    var onIdentity: ((String) -> Void)?
    private(set) var framing: EdifierFraming?
    private(set) var diagnostics: [String] = []
    private var decoder = EdifierFrameDecoder()
    private var requests: [Request] = []
    private var inFlight: Request?
    private var deadline: TimeInterval = 0
    private var nextSend: TimeInterval = 0
    private var nextPoll: TimeInterval = .infinity
    private var lastResponse: TimeInterval = 0
    private var expected: [EdifierFeature: Data] = [:]
    private var ancPrefix: UInt8?
    private var started = false
    private var retired = false

    var isReady: Bool { started && !retired && framing != nil && device.controlState == .ready }

    init(device: HeadphoneDevice) { self.device = device }

    func log(_ message: String) {
        diagnostics.append(message)
        if diagnostics.count > 100 { diagnostics.removeFirst(diagnostics.count - 100) }
    }

    func start(now: TimeInterval) {
        guard !retired else { return }
        reset()
        started = true
        device.controlState = .probing
        let preferred = device.edifierProfile.preferredFraming
        // Both formats are probed with reads only. No model is inferred from a write ACK.
        for candidate in [preferred, preferred == .connex ? .legacy : .connex] {
            for command in [UInt8(0xD8), 0xD0, 0xC9] {
                requests.append(Request(command: command, framing: candidate))
            }
        }
        lastResponse = now
        log("Begin read-only protocol detection (\(device.edifierProfile.rawValue))")
        publish()
    }

    func reset() {
        guard !retired else { return }
        started = false
        requests.removeAll()
        inFlight = nil
        framing = nil
        decoder = EdifierFrameDecoder()
        nextSend = 0
        nextPoll = .infinity
        expected.removeAll()
        ancPrefix = nil
        device.supportedFeatures = []
        device.pendingFeatures = []
        device.hasANCState = false
        device.gameModeEnabled = nil
        device.equalizerPreset = nil
        device.edifierANCIndex = nil
        device.edifierNoiseValue = nil
        device.edifierScene = nil
        device.controlError = nil
        device.isCharging = false
        device.batteryIsFromControl = false
    }

    func disconnect(state: HeadphoneControlState = .disconnected) {
        guard !retired else { return }
        reset()
        device.controlState = state
        publish()
    }

    /// Detach a losing transport without resetting the model owned by the active transport.
    func retire() {
        retired = true
        started = false
        requests.removeAll()
        inFlight = nil
        expected.removeAll()
        decoder = EdifierFrameDecoder()
        onUpdate = nil
        onIdentity = nil
    }

    func tick(now: TimeInterval) {
        guard started, !retired else { return }
        guard device.controlState == .probing || device.controlState == .ready else { return }
        if let request = inFlight, now >= deadline {
            log("Timeout \(hex(request.command))")
            if let feature = request.feature, request.confirmation {
                device.pendingFeatures.remove(feature)
                expected.removeValue(forKey: feature)
                device.controlError = "The headset did not confirm the change. Retry or refresh."
                publish()
            }
            inFlight = nil
            nextSend = now + request.delay
        }
        if framing != nil, now - lastResponse > 60 {
            device.controlState = .unavailable
            requests.removeAll()
            inFlight = nil
            device.pendingFeatures = []
            expected.removeAll()
            publish()
            return
        }
        guard inFlight == nil, now >= nextSend else { return }
        if requests.isEmpty, framing == nil {
            device.controlState = .unavailable
            publish()
            return
        }
        if requests.isEmpty, now >= nextPoll {
            refresh(includeMetadata: false)
            nextPoll = now + 15
        }
        guard !requests.isEmpty else { return }
        let request = requests.removeFirst()
        let wireFraming = request.framing ?? framing ?? device.edifierProfile.preferredFraming
        let bytes = EdifierPacket(command: request.command, data: request.payload, isConnex: wireFraming == .connex).toData()
        inFlight = request
        deadline = now + (framing == nil ? 1 : 1.5)
        log("TX \(wireFraming.rawValue) \(hex(request.command)) \(request.payload.map(hex).joined(separator: " "))")
        if send?(bytes) != true { transportFailed("Bluetooth could not send the command.") }
    }

    func transportFailed(_ message: String) {
        guard !retired else { return }
        requests.removeAll()
        inFlight = nil
        device.pendingFeatures = []
        expected.removeAll()
        device.controlState = .unavailable
        device.controlError = message
        log(message)
        publish()
    }

    func receive(_ data: Data, now: TimeInterval) {
        guard started, !retired else { return }
        for packet in decoder.append(data, now: now) { receive(packet, now: now) }
    }

    func receive(_ packet: EdifierPacket, now: TimeInterval) {
        guard started, !retired else { return }
        guard packet.direction != EdifierPacket.requestInit, packet.app == 0xEC || !packet.isConnex else { return }
        guard device.controlState == .probing || device.controlState == .ready else { return }
        log("RX \(packet.framing.rawValue) \(hex(packet.command)) \(packet.data.map(hex).joined(separator: " "))")
        if framing == nil {
            guard packet.direction == 0xBB, let request = inFlight,
                  request.framing == packet.framing, request.command == packet.command,
                  isProbeResponse(packet) else { return }
            framing = packet.framing
            requests.removeAll()
            inFlight = nil
            nextSend = now + 0.15
            nextPoll = now + 15
            device.controlState = .ready
            refresh(includeMetadata: true)
            log("Selected \(packet.framing.rawValue) framing")
        }
        guard packet.framing == framing else { return }
        lastResponse = now
        let matched = inFlight?.command == packet.command
        // Set responses can be acknowledgements even with a BB header. Only GET values update state.
        if matched, let request = inFlight, request.isWrite {
            if packet.direction == 0xCC, packet.data.first != 1 {
                device.controlError = "The headset rejected the change."
                if let feature = request.feature {
                    requests.removeAll { $0.feature == feature }
                    expected.removeValue(forKey: feature)
                    device.pendingFeatures.remove(feature)
                }
            }
            finish(request, now: now)
            publish()
            return
        }
        guard packet.direction == 0xBB else { return }
        // Ignore old push updates while a mutation awaits its own GET confirmation.
        let confirmation = matched && inFlight?.confirmation == true
        let valid = apply(packet, confirmation: confirmation)
        if valid, matched, let request = inFlight { finish(request, now: now) }
        if valid { publish() }
    }

    private func isProbeResponse(_ packet: EdifierPacket) -> Bool {
        switch packet.command {
        case 0xD0: return packet.data.count == 1 && packet.data.first! <= 100
        case 0xC9: return Self.deviceName(packet.data) != nil
        case 0xD8: return !packet.data.isEmpty
        default: return false
        }
    }

    private func finish(_ request: Request, now: TimeInterval) {
        inFlight = nil
        nextSend = now + request.delay
    }

    func refresh(includeMetadata: Bool = false) {
        guard started, !retired, framing != nil else { return }
        if includeMetadata {
            for command in [UInt8(0xC8), 0xC9, 0xC6, 0xD8] { enqueue(Request(command: command)) }
        }
        enqueue(Request(command: 0xD0))
        if device.edifierProfile == .fit900NB { enqueue(Request(command: 0xF2)) }
        for (feature, command) in [(EdifierFeature.noiseControl, UInt8(0xCC)), (.gameMode, 0x08), (.equalizer, 0xD5)] {
            if device.edifierProfile.queries(feature), !device.pendingFeatures.contains(feature) {
                enqueue(Request(command: command, feature: feature))
            }
        }
    }

    private func enqueue(_ request: Request) {
        guard !requests.contains(where: { $0.command == request.command }), inFlight?.command != request.command else { return }
        requests.append(request)
    }

    func setANC(_ mode: ANCMode, level: UInt8?) {
        guard device.canControl(.noiseControl) else { return }
        if let index = ancPrefix {
            let options = EdifierNoiseOption.options(index: index).filter { $0.mode == mode }
            let preferred = device.edifierCancellationSelection
            let preferredOption = mode == .cancellation && preferred?.index == index
                ? options.first(where: { $0.value == preferred?.value }) : nil
            guard let option = preferredOption ?? options.first else { return }
            setNoiseOption(option.value, level: level)
            return
        }
        if let level, !(3...9).contains(level) || !device.supportedFeatures.contains(.ambientLevel) { return }
        let modeByte: UInt8 = mode == .off ? 1 : (mode == .cancellation ? 2 : 3)
        var payload = Data([modeByte])
        if mode == .awareness, device.supportedFeatures.contains(.ambientLevel) {
            payload.append(level ?? UInt8(clamping: device.ancLevel))
        }
        mutate(feature: .noiseControl, set: 0xC1, payload: payload, get: 0xCC, target: payload, delay: 1.8)
    }

    func setNoiseOption(_ value: UInt8, level: UInt8? = nil) {
        guard device.canControl(.noiseControl), let index = ancPrefix,
              let option = EdifierNoiseOption.options(index: index).first(where: { $0.value == value }) else { return }
        if let level, option.mode != .awareness || !(3...9).contains(level) || !device.supportedFeatures.contains(.ambientLevel) { return }
        var payload = Data([index, value])
        // The indexed setter takes [index, value]; gain is optional when changing ambient gain.
        if let level { payload.append(level) }
        mutate(feature: .noiseControl, set: 0xC1, payload: payload, get: 0xCC,
               target: Data(payload.dropFirst()), delay: 2.2)
    }

    func setGameMode(_ enabled: Bool) {
        if device.supportedFeatures.contains(.sceneMode) { setScene(enabled ? .game : .music); return }
        guard device.canControl(.gameMode) else { return }
        let target = Data([enabled ? 1 : 0])
        mutate(feature: .gameMode, set: 0x09, payload: target, get: 0x08, target: target)
    }

    func setScene(_ scene: EdifierScene) {
        guard device.canControl(.sceneMode) else { return }
        let target = Data([scene.rawValue])
        mutate(feature: .sceneMode, set: 0x09, payload: target, get: 0x08, target: target)
    }

    func setEqualizer(_ preset: EqualizerPreset) {
        guard device.canControl(.equalizer) else { return }
        let target = Data([EdifierProfile.effectByte(preset)])
        mutate(feature: .equalizer, set: 0xC4, payload: target, get: 0xD5, target: target)
    }

    private func mutate(feature: EdifierFeature, set: UInt8, payload: Data, get: UInt8, target: Data, delay: TimeInterval = 0.4) {
        guard isReady else { return }
        requests.removeAll { $0.feature == feature || $0.command == get }
        expected[feature] = target
        device.pendingFeatures.insert(feature)
        device.controlError = nil
        requests.insert(contentsOf: [Request(command: set, payload: payload, feature: feature, delay: delay),
                                     Request(command: get, feature: feature, confirmation: true)], at: 0)
        publish()
    }

    private func apply(_ packet: EdifierPacket, confirmation: Bool) -> Bool {
        let bytes = [UInt8](packet.data)
        switch packet.command {
        case 0xD0:
            guard bytes.count == 1, bytes[0] <= 100 else { return false }
            device.batteryLevel = Int(bytes[0])
            device.batteryIsFromControl = true
        case 0xF2:
            guard device.edifierProfile == .fit900NB, bytes.count >= 6, bytes[0] == 4,
                  bytes[3] <= 100, bytes[4] <= 1 else { return false }
            device.batteryLevel = Int(bytes[3])
            device.batteryIsFromControl = true
            device.isCharging = bytes[4] == 1
        case 0xCC:
            guard device.edifierProfile.queries(.noiseControl), (1...3).contains(bytes.count) else { return false }
            let indexed = bytes.count >= 2 && !EdifierNoiseOption.options(index: bytes[0]).isEmpty
            let modeIndex = indexed ? 1 : 0
            let mode: ANCMode
            if indexed {
                guard let option = EdifierNoiseOption.options(index: bytes[0]).first(where: { $0.value == bytes[1] }) else { return false }
                mode = option.mode
            } else {
                guard bytes.count <= 2, (1...3).contains(bytes[0]) else { return false }
                mode = bytes[0] == 1 ? .off : (bytes[0] == 2 ? .cancellation : .awareness)
            }
            if device.pendingFeatures.contains(.noiseControl), !confirmation { return false }
            ancPrefix = indexed ? bytes[0] : nil
            device.edifierANCIndex = ancPrefix
            device.edifierNoiseValue = indexed ? bytes[1] : nil
            if indexed, mode == .cancellation {
                device.edifierCancellationSelection = (index: bytes[0], value: bytes[1])
            }
            device.ancMode = mode
            device.hasANCState = true
            device.supportedFeatures.insert(.noiseControl)
            if bytes.count > modeIndex + 1, (3...9).contains(bytes[modeIndex + 1]) {
                device.ancLevel = Int(bytes[modeIndex + 1])
                device.supportedFeatures.insert(.ambientLevel)
            }
            if confirmation, let target = expected[.noiseControl] {
                let targetBytes = [UInt8](target)
                let matches = targetBytes[0] == bytes[modeIndex] &&
                    (targetBytes.count == 1 || (bytes.count > modeIndex + 1 && targetBytes[1] == bytes[modeIndex + 1]))
                confirm(.noiseControl, matches: matches)
            }
        case 0x08:
            guard device.edifierProfile.queries(.gameMode), !bytes.isEmpty else { return false }
            let sceneResponse = device.edifierProfile == .fit900NB && (1...2).contains(bytes.count) && bytes[0] <= 2
            guard sceneResponse || (bytes.count == 1 && bytes[0] <= 1) else { return false }
            let feature: EdifierFeature = sceneResponse ? .sceneMode : .gameMode
            if device.pendingFeatures.contains(feature), !confirmation { return false }
            device.gameModeEnabled = bytes[0] == 1
            device.supportedFeatures.insert(feature)
            if sceneResponse { device.edifierScene = EdifierScene(rawValue: bytes[0]) }
            if confirmation { confirm(feature, matches: expected[feature]?.first == bytes[0]) }
        case 0xD5:
            guard device.edifierProfile.queries(.equalizer), bytes.count == 1,
                  let preset = EdifierProfile.preset(bytes[0]) else { return false }
            if device.pendingFeatures.contains(.equalizer), !confirmation { return false }
            device.equalizerPreset = preset
            device.supportedFeatures.insert(.equalizer)
            if confirmation { confirm(.equalizer, matches: expected[.equalizer] == packet.data) }
        case 0xC8:
            guard bytes.count == 6, bytes.contains(where: { $0 != 0 }), bytes.contains(where: { $0 != 0xFF }) else { return false }
            onIdentity?(bytes.map { String(format: "%02X", $0) }.joined(separator: ":"))
        case 0xC9:
            guard let name = Self.deviceName(packet.data) else { return false }
            if name.lowercased() != "edifier ble" {
                device.name = name
                let profile = EdifierProfile.resolve(name: name)
                if profile != .unknown { device.edifierProfile = profile }
            }
        case 0xC6:
            guard bytes.count == 3 else { return false }
            device.firmwareVersion = bytes.map(String.init).joined(separator: ".")
        case 0xD8:
            guard !bytes.isEmpty else { return false }
            // D8 layouts vary. Keep the raw fingerprint in diagnostics; do not guess capability bits.
        default: return false
        }
        device.lastUpdated = Date()
        return true
    }

    private func confirm(_ feature: EdifierFeature, matches: Bool) {
        expected.removeValue(forKey: feature)
        device.pendingFeatures.remove(feature)
        if !matches { device.controlError = "The headset reported a different setting. Its current value is shown." }
    }

    private static func deviceName(_ data: Data) -> String? {
        guard let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)),
              !name.isEmpty, name.count <= 100, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return name
    }

    private func hex(_ value: UInt8) -> String { String(format: "%02X", value) }
    private func publish() { onUpdate?(device) }
}
