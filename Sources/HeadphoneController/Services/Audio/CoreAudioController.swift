import Foundation
import CoreAudio
import Combine

public class CoreAudioController: ObservableObject {
    @Published public var currentVolume: Float = 0.5
    @Published public var isMuted: Bool = false
    @Published public var defaultOutputDeviceName: String = ""
    @Published public var defaultOutputDeviceID: AudioDeviceID = 0
    
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    
    public init() {
        refresh()
        setupListeners()
    }
    
    deinit {
        removeListeners()
    }
    
    public func refresh() {
        guard let deviceID = getDefaultOutputDeviceID() else { return }
        self.defaultOutputDeviceID = deviceID
        self.defaultOutputDeviceName = getDeviceName(deviceID) ?? "Unknown Device"
        self.currentVolume = getDeviceVolume(deviceID) ?? 0.5
        self.isMuted = getDeviceMute(deviceID)
    }
    
    // MARK: - CoreAudio Helpers
    
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
    
    public func getDeviceVolume(_ deviceID: AudioDeviceID) -> Float? {
        var volume: Float32 = 0.0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &volume
        )
        guard status == noErr else { return nil }
        return volume
    }
    
    public func getDeviceMute(_ deviceID: AudioDeviceID) -> Bool {
        var mute: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &mute
        )
        guard status == noErr else { return false }
        return mute != 0
    }
    
    public func setVolume(_ volume: Float) {
        guard let deviceID = getDefaultOutputDeviceID() else { return }
        var targetVolume = max(0.0, min(1.0, volume))
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let dataSize = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &targetVolume
        )
        DispatchQueue.main.async {
            self.currentVolume = targetVolume
        }
    }
    
    public func setMuted(_ muted: Bool) {
        guard let deviceID = getDefaultOutputDeviceID() else { return }
        var muteValue: UInt32 = muted ? 1 : 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &muteValue
        )
        DispatchQueue.main.async {
            self.isMuted = muted
        }
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
            // Check if device has output streams
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
        guard let match = devices.first(where: { $0.name.localizedCaseInsensitiveContains(targetName) }) else {
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
    
    // MARK: - CoreAudio Listeners
    
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
