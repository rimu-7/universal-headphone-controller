import Foundation

public enum EdifierFeature: String, Hashable, CaseIterable {
    case noiseControl, ambientLevel, gameMode, sceneMode, equalizer
}

public enum EdifierScene: UInt8, CaseIterable, Identifiable {
    case music = 0, game = 1, spatial = 2
    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .music: return "Music"
        case .game: return "Game"
        case .spatial: return "Spatial"
        }
    }
}

public struct EdifierNoiseOption: Identifiable {
    public let value: UInt8
    public let title: String
    public let mode: ANCMode
    public var id: UInt8 { value }

    public static func options(index: UInt8) -> [Self] {
        let entries: [(String, ANCMode)]
        switch index {
        case 0x10, 0x2F:
            entries = [("Deep Cancellation", .cancellation), ("Comfort Cancellation", .cancellation),
                       ("Wind Reduction", .cancellation), ("Ambient Sound", .awareness), ("Off", .off)]
        case 0x1B:
            entries = [("Deep Cancellation", .cancellation), ("Comfort Cancellation", .cancellation),
                       ("Wideband Cancellation", .cancellation), ("Wind Reduction", .cancellation), ("Ambient Sound", .awareness), ("Off", .off)]
        case 0x1F:
            entries = [("Deep Cancellation", .cancellation), ("Comfort Cancellation", .cancellation),
                       ("Light Cancellation", .cancellation), ("Ambient Sound", .awareness), ("Wind Reduction", .cancellation), ("Off", .off)]
        case 0x2E:
            entries = [("Adaptive Cancellation", .cancellation), ("Deep Cancellation", .cancellation),
                       ("Comfort Cancellation", .cancellation), ("Wind Reduction", .cancellation), ("Ambient Sound", .awareness), ("Off", .off)]
        default: return []
        }
        return entries.enumerated().map { Self(value: UInt8($0.offset + 1), title: $0.element.0, mode: $0.element.1) }
    }
}

public enum HeadphoneControlState: String {
    case disconnected, searching, connecting, discovering, probing, ready, unavailable, bluetoothOff, permissionDenied

    public var message: String {
        switch self {
        case .disconnected: return "Headphone controls disconnected"
        case .searching: return "Searching for headphone controls…"
        case .connecting: return "Connecting to headphone controls…"
        case .discovering: return "Discovering headphone controls…"
        case .probing: return "Checking supported controls…"
        case .ready: return "Headphone controls ready"
        case .unavailable: return "Headphone controls did not respond. Retry controls."
        case .bluetoothOff: return "Turn on Bluetooth to use headphone controls."
        case .permissionDenied: return "Allow Bluetooth in System Settings → Privacy & Security."
        }
    }
}

/// Model policy is independent of discovery, transport and UI. Unknown models get conservative support.
public enum EdifierProfile: String {
    case fit900NB, w820NB, w820NBDoubleGold, w200BTPlus, unknown

    public static let serviceSuffix = "-1A48-11E9-AB14-D663BD873D93"
    public static let knownServices = ["48090000", "48093801", "48097901", "48092801", "4809E901"]
        .map { $0 + serviceSuffix }

    public static func resolve(name: String, service: String? = nil) -> Self {
        let name = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let service = service?.uppercased() ?? ""
        if name.contains("fit900nbturbo") { return .unknown }
        if name.contains("fit900") || service.hasPrefix("4809E901") { return .fit900NB }
        if service.hasPrefix("48097901") || (name.contains("w820") && name.contains("gold")) { return .w820NBDoubleGold }
        if service.hasPrefix("48093801") || name.contains("w820nb") { return .w820NB }
        if service.hasPrefix("48092801") || name.contains("w200btplus") { return .w200BTPlus }
        return .unknown
    }

    public static func matches(name: String) -> Bool {
        let name = name.lowercased()
        return ["edifier", "fit900", "neobuds", "stax spirit", "w820nb", "w830nb", "w800bt", "w200bt"].contains { name.contains($0) }
    }

    public static func isControlService(_ uuid: String) -> Bool {
        let uuid = uuid.uppercased()
        return (uuid.hasPrefix("4809") && uuid.hasSuffix(serviceSuffix)) || uuid == "00001000-0000-1000-8991-00805F9B34FB"
    }

    public var preferredFraming: EdifierFraming { self == .fit900NB || self == .unknown ? .connex : .legacy }

    public func queries(_ feature: EdifierFeature) -> Bool {
        switch (self, feature) {
        case (.w200BTPlus, .noiseControl), (.w200BTPlus, .ambientLevel), (.w200BTPlus, .gameMode),
             (.w820NB, .equalizer): return false
        // D5 is ambiguous on unknown models (including game-mode notifications).
        case (.unknown, .equalizer), (.fit900NB, .equalizer): return false
        default: return true
        }
    }

    public func presetTitle(_ preset: EqualizerPreset) -> String {
        if self == .fit900NB { return "Preset \(Self.effectByte(preset) + 1)" }
        switch preset {
        case .defaultPreset: return "Classic"
        case .voices: return "Pop"
        case .treble: return "Classical"
        case .bass: return "Rock"
        }
    }

    public static func effectByte(_ preset: EqualizerPreset) -> UInt8 {
        switch preset {
        case .defaultPreset: return 0
        case .voices: return 1
        case .treble: return 2
        case .bass: return 3
        }
    }

    public static func preset(_ byte: UInt8) -> EqualizerPreset? {
        switch byte {
        case 0: return .defaultPreset
        case 1: return .voices
        case 2: return .treble
        case 3: return .bass
        default: return nil
        }
    }
}
