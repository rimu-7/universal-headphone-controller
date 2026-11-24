import Foundation
import Combine

public class HeadphoneDevice: ObservableObject, Identifiable {
    public let id: String
    @Published public var name: String
    public let brand: HeadphoneBrand
    @Published public var isConnected: Bool
    @Published public var batteryLevel: Int?
    @Published public var isCharging: Bool
    @Published public var ancMode: ANCMode
    @Published public var ancLevel: Int
    @Published public var gameModeEnabled: Bool?
    @Published public var equalizerPreset: EqualizerPreset?
    @Published public var isCurrentAudioOutput: Bool
    @Published public var lastUpdated: Date
    @Published public var controlState: HeadphoneControlState = .disconnected
    @Published public var supportedFeatures: Set<EdifierFeature> = []
    @Published public var pendingFeatures: Set<EdifierFeature> = []
    @Published public var hasANCState = false
    @Published public var controlError: String?
    @Published public var firmwareVersion: String?
    @Published public var edifierProfile: EdifierProfile = .unknown
    @Published public var edifierANCIndex: UInt8?
    @Published public var edifierNoiseValue: UInt8?
    @Published public var edifierScene: EdifierScene?
    var batteryIsFromControl = false
    // Updated only by confirmed readback, retained when the control view is recreated.
    var edifierCancellationSelection: (index: UInt8, value: UInt8)?

    public func canControl(_ feature: EdifierFeature) -> Bool {
        if brand == .huawei { return isConnected }
        return controlState == .ready && supportedFeatures.contains(feature) && !pendingFeatures.contains(feature)
    }
    
    public init(
        id: String,
        name: String,
        brand: HeadphoneBrand,
        isConnected: Bool = false,
        batteryLevel: Int? = nil,
        isCharging: Bool = false,
        ancMode: ANCMode = .off,
        ancLevel: Int = 0,
        gameModeEnabled: Bool? = nil,
        equalizerPreset: EqualizerPreset? = nil,
        isCurrentAudioOutput: Bool = false
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.isConnected = isConnected
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.ancMode = ancMode
        self.ancLevel = ancLevel
        self.gameModeEnabled = gameModeEnabled
        self.equalizerPreset = equalizerPreset
        self.isCurrentAudioOutput = isCurrentAudioOutput
        self.lastUpdated = Date()
    }
}
