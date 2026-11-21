import Foundation
import Combine
import SwiftUI

public class HeadphoneManager: ObservableObject {
    public static let shared = HeadphoneManager()
    
    @Published public var devices: [HeadphoneDevice] = []
    @Published public var selectedDeviceID: String?
    @Published public var audioController = CoreAudioController()
    
    private let huaweiManager = HuaweiRFCOMMManager.shared
    private let edifierManager = EdifierBLEManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        setupBindings()
        start()
    }
    
    public var activeDevice: HeadphoneDevice? {
        if let selID = selectedDeviceID, let found = devices.first(where: { $0.id == selID }) {
            return found
        }
        // Fallback to first connected device or first available
        return devices.first(where: { $0.isConnected }) ?? devices.first
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
        
        edifierManager.queryBattery()
        edifierManager.queryANCMode()
        edifierManager.queryGameMode()
        
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
        
        audioController.$defaultOutputDeviceName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAudioOutputStatus()
            }
            .store(in: &cancellables)
    }
    
    private func handleDeviceUpdate(_ device: HeadphoneDevice) {
        DispatchQueue.main.async {
            if let index = self.devices.firstIndex(where: {
                $0.id == device.id || $0.name == device.name || ($0.brand == device.brand && device.brand != .generic)
            }) {
                self.devices[index] = device
            } else {
                self.devices.append(device)
            }
            self.updateAudioOutputStatus()
            self.objectWillChange.send()
        }
    }
    
    public func updateAudioOutputStatus() {
        let currentOut = audioController.defaultOutputDeviceName.lowercased()
        for dev in devices {
            let devLower = dev.name.lowercased()
            let isMatch = !currentOut.isEmpty && (
                currentOut.contains(devLower) ||
                devLower.contains(currentOut) ||
                (dev.brand == .edifier && currentOut.contains("edifier")) ||
                (dev.brand == .huawei && (currentOut.contains("huawei") || currentOut.contains("freelace")))
            )
            if dev.isCurrentAudioOutput != isMatch {
                dev.isCurrentAudioOutput = isMatch
            }
        }
    }
    
    // MARK: - Actions
    
    public func setANCMode(for device: HeadphoneDevice, mode: ANCMode) {
        switch device.brand {
        case .huawei:
            huaweiManager.setANCMode(mode)
        case .edifier:
            edifierManager.setANCMode(mode)
        case .generic:
            break
        }
    }
    
    public func setGameMode(for device: HeadphoneDevice, enabled: Bool) {
        switch device.brand {
        case .huawei:
            huaweiManager.setLowLatency(enabled: enabled)
        case .edifier:
            edifierManager.setGameMode(enabled: enabled)
        case .generic:
            break
        }
    }
    
    public func setEqualizer(for device: HeadphoneDevice, preset: EqualizerPreset) {
        switch device.brand {
        case .huawei:
            huaweiManager.setEqualizer(preset)
        case .edifier:
            edifierManager.setEqualizer(preset)
        case .generic:
            break
        }
    }
    
    public func routeAudioTo(device: HeadphoneDevice) {
        _ = audioController.setDefaultOutputDevice(named: device.name)
        updateAudioOutputStatus()
    }
    
    public func setVolume(_ volume: Float) {
        audioController.setVolume(volume)
    }
    
    public func toggleMute() {
        audioController.setMuted(!audioController.isMuted)
    }
}
