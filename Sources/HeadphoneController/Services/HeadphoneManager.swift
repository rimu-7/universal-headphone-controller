import Foundation
import Combine
import SwiftUI

public class HeadphoneManager: ObservableObject {
    public static let shared = HeadphoneManager()
    
    @Published public var devices: [HeadphoneDevice] = []
    @Published public var selectedDeviceID: String?
    @Published public var audioController = CoreAudioController()
    
    private lazy var huaweiManager = HuaweiRFCOMMManager.shared
    private lazy var edifierManager = EdifierBLEManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    public init(startAutomatically: Bool = true) {
        if startAutomatically {
            setupBindings()
            // Let AppKit finish launching before starting Bluetooth discovery and permission requests.
            DispatchQueue.main.async { [weak self] in self?.start() }
        }
    }
    
    public var activeDevice: HeadphoneDevice? {
        if let selID = selectedDeviceID, let found = devices.first(where: { $0.id == selID }) {
            return found
        }
        // Fallback to first connected device or first available
        return devices.first(where: { $0.isConnected && $0.isCurrentAudioOutput }) ?? devices.first(where: { $0.isConnected }) ?? devices.first
    }
    
    public var menuBarTitle: String {
        guard let active = activeDevice, active.isConnected else {
            return "Headphones"
        }
        if let batt = active.batteryLevel {
            return "\(batt)%"
        }
        return active.name
    }
    
    public var menuBarIcon: String {
        guard let active = activeDevice, active.isConnected else {
            return "headphones"
        }
        if active.brand == .edifier && !active.hasANCState { return "headphones" }
        switch active.ancMode {
        case .cancellation:
            return "ear.and.waveform"
        case .awareness:
            return "waveform"
        case .off:
            return "headphones"
        }
    }
    
    public func start() {
        huaweiManager.start()
        edifierManager.start()
        updateAudioOutputStatus()
    }
    
    public func refreshAll() {
        huaweiManager.scanAndConnect()
        huaweiManager.queryBattery()
        huaweiManager.queryANCMode()
        
        edifierManager.refresh()
        
        audioController.refresh()
        updateAudioOutputStatus()
    }
    
    private func setupBindings() {
        huaweiManager.onDeviceUpdated = { [weak self] device in
            self?.handleDeviceUpdate(device)
        }
        
        edifierManager.onDeviceUpdated = { [weak self] device in
            self?.handleDeviceUpdate(device)
        }
        edifierManager.onDeviceRemoved = { [weak self] id in
            self?.devices.removeAll { $0.id == id }
            if self?.selectedDeviceID == id { self?.selectedDeviceID = nil }
        }
        
        audioController.$defaultOutputDeviceName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAudioOutputStatus()
            }
            .store(in: &cancellables)
    }
    
    private func handleDeviceUpdate(_ device: HeadphoneDevice) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handleDeviceUpdate(device) }
            return
        }
        if let index = self.devices.firstIndex(where: {
            $0.id == device.id
        }) {
            let existing = self.devices[index]
            if existing !== device {
                existing.name = device.name
                existing.isConnected = device.isConnected
                existing.isCharging = device.isCharging
                if let batt = device.batteryLevel { existing.batteryLevel = batt }
                existing.ancMode = device.ancMode
                existing.ancLevel = device.ancLevel
                if let game = device.gameModeEnabled { existing.gameModeEnabled = game }
                if let eq = device.equalizerPreset { existing.equalizerPreset = eq }
                existing.lastUpdated = device.lastUpdated
                existing.controlState = device.controlState
                existing.supportedFeatures = device.supportedFeatures
                existing.pendingFeatures = device.pendingFeatures
                existing.hasANCState = device.hasANCState
                existing.controlError = device.controlError
                existing.firmwareVersion = device.firmwareVersion
                existing.edifierProfile = device.edifierProfile
                existing.edifierANCIndex = device.edifierANCIndex
                existing.edifierNoiseValue = device.edifierNoiseValue
                existing.edifierScene = device.edifierScene
                existing.edifierCancellationSelection = device.edifierCancellationSelection
            } else {
                self.devices[index] = device
            }
        } else {
            self.devices.append(device)
        }
        self.updateAudioOutputStatus()
        self.objectWillChange.send()
    }

    public func updateAudioOutputStatus() {
        let currentOut = audioController.defaultOutputDeviceName.lowercased()
        let exactMatches = devices.filter { !$0.name.isEmpty && $0.name.lowercased() == currentOut }
        let partialMatches = devices.filter { !$0.name.isEmpty &&
            (currentOut.contains($0.name.lowercased()) || $0.name.lowercased().contains(currentOut)) }
        for dev in devices {
            let devLower = dev.name.lowercased()
            let isMatch = !currentOut.isEmpty && !devLower.isEmpty && dev.isConnected &&
                (exactMatches.count == 1 ? exactMatches.first?.id == dev.id :
                    (exactMatches.isEmpty && partialMatches.count == 1 && partialMatches.first?.id == dev.id))
            if dev.isCurrentAudioOutput != isMatch {
                dev.isCurrentAudioOutput = isMatch
            }
        }
    }
    
    // MARK: - Actions
    
    public func setANCMode(for device: HeadphoneDevice, mode: ANCMode, ambientLevel: UInt8? = nil) {
        switch device.brand {
        case .huawei:
            huaweiManager.setANCMode(mode)
        case .edifier:
            edifierManager.setANCMode(for: device.id, mode: mode, ambientLevel: ambientLevel)
        case .generic:
            break
        }
    }
    
    public func setGameMode(for device: HeadphoneDevice, enabled: Bool) {
        switch device.brand {
        case .huawei:
            huaweiManager.setLowLatency(enabled: enabled)
        case .edifier:
            edifierManager.setGameMode(for: device.id, enabled: enabled)
        case .generic:
            break
        }
    }
    
    public func setEqualizer(for device: HeadphoneDevice, preset: EqualizerPreset) {
        switch device.brand {
        case .huawei:
            huaweiManager.setEqualizer(preset)
        case .edifier:
            edifierManager.setEqualizer(for: device.id, preset: preset)
        case .generic:
            break
        }
    }
    
    public func routeAudioTo(device: HeadphoneDevice) {
        _ = audioController.setDefaultOutputDevice(named: device.name)
        updateAudioOutputStatus()
    }

    public func retryControls(for device: HeadphoneDevice) { edifierManager.retry(deviceID: device.id) }

    public func setEdifierNoise(for device: HeadphoneDevice, value: UInt8, level: UInt8? = nil) {
        edifierManager.setNoiseOption(for: device.id, value: value, level: level)
    }

    public func setEdifierScene(for device: HeadphoneDevice, scene: EdifierScene) {
        edifierManager.setScene(for: device.id, scene: scene)
    }

    public func copyDiagnostics(for device: HeadphoneDevice) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(edifierManager.diagnosticReport(for: device.id), forType: .string)
    }
    
    public func setVolume(_ volume: Float) {
        audioController.setVolume(volume)
    }
    
    public func toggleMute() {
        audioController.setMuted(!audioController.isMuted)
    }
}
