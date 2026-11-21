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
