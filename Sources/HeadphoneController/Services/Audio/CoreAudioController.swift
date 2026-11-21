import Foundation
import CoreAudio
import Combine

public class CoreAudioController: ObservableObject {
    @Published public var currentVolume: Float = 0.5
    @Published public var isMuted: Bool = false
    @Published public var defaultOutputDeviceName: String = ""
    @Published public var defaultOutputDeviceID: AudioDeviceID = 0
    
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var volumePollTimer: Timer?
    
    public init() {
        refresh()
        setupListeners()
        startVolumePolling()
    }
    
    deinit {
        volumePollTimer?.invalidate()
        removeListeners()
    }
    
    public func refresh() {
        // 1. Get default device info
        if let deviceID = getDefaultOutputDeviceID() {
            self.defaultOutputDeviceID = deviceID
            self.defaultOutputDeviceName = getDeviceName(deviceID) ?? "Unknown Device"
        }
        
        // 2. Read true system master output volume
        let vol = getSystemVolume()
        let mute = getSystemMute()
        
        DispatchQueue.main.async {
            self.currentVolume = vol
            self.isMuted = mute
        }
    }
    
    // MARK: - System Volume Control (Smooth & Universal)
    
    public func getSystemVolume() -> Float {
        let script = NSAppleScript(source: "output volume of (get volume settings)")
        var error: NSDictionary?
        if let res = script?.executeAndReturnError(&error) {
            return Float(res.int32Value) / 100.0
        }
        return 0.5
    }
    
    public func getSystemMute() -> Bool {
        let script = NSAppleScript(source: "output muted of (get volume settings)")
        var error: NSDictionary?
        if let res = script?.executeAndReturnError(&error) {
            return res.booleanValue
        }
        return false
    }
    
    public func setVolume(_ volume: Float) {
        let clamped = max(0.0, min(1.0, volume))
        let intVal = Int(round(clamped * 100))
        
        // Optimistic UI update
        self.currentVolume = clamped
        
        // Execute system volume change in background queue to avoid UI hitching
        DispatchQueue.global(qos: .userInteractive).async {
            let script = NSAppleScript(source: "set volume output volume \(intVal)")
            script?.executeAndReturnError(nil)
        }
    }
    
    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        DispatchQueue.global(qos: .userInteractive).async {
            let script = NSAppleScript(source: "set volume output muted \(muted ? "true" : "false")")
            script?.executeAndReturnError(nil)
        }
    }
    
    // MARK: - Device Routing via CoreAudio
    
    public func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }
    
    public func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedString: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanagedString) { ptr in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                ptr
            )
        }
        guard status == noErr, let cfStr = unmanagedString?.takeRetainedValue() else {
            return nil
        }
        return cfStr as String
    }
    
    public func getAllOutputDevices() -> [(id: AudioDeviceID, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }
        
        var result: [(id: AudioDeviceID, name: String)] = []
        for id in deviceIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let streamStatus = AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize)
            if streamStatus == noErr && streamSize > 0 {
                if let name = getDeviceName(id) {
                    result.append((id: id, name: name))
                }
            }
        }
        return result
    }
    
    public func setDefaultOutputDevice(named targetName: String) -> Bool {
        let devices = getAllOutputDevices()
        guard let match = devices.first(where: {
            $0.name.localizedCaseInsensitiveContains(targetName) ||
            targetName.localizedCaseInsensitiveContains($0.name)
        }) else {
            return false
        }
        return setDefaultOutputDevice(id: match.id)
    }
    
    public func setDefaultOutputDevice(id: AudioDeviceID) -> Bool {
        var targetID = id
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &targetID
        )
        if status == noErr {
            refresh()
            return true
        }
        return false
    }
    
    // MARK: - Listeners & Polling
    
    private func setupListeners() {
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        defaultDeviceListenerBlock = { [weak self] (_, _) in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main,
            defaultDeviceListenerBlock!
        )
    }
    
    private func startVolumePolling() {
        volumePollTimer?.invalidate()
        volumePollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let vol = self.getSystemVolume()
            let mute = self.getSystemMute()
            DispatchQueue.main.async {
                if abs(self.currentVolume - vol) > 0.02 {
                    self.currentVolume = vol
                }
                if self.isMuted != mute {
                    self.isMuted = mute
                }
            }
        }
    }
    
    private func removeListeners() {
        if let block = defaultDeviceListenerBlock {
            var defaultDeviceAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultDeviceAddress,
                DispatchQueue.main,
                block
            )
        }
    }
}
