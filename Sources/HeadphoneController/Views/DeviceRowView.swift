import SwiftUI

public struct DeviceRowView: View {
    @ObservedObject public var device: HeadphoneDevice
    public let manager: HeadphoneManager
    
    public init(device: HeadphoneDevice, manager: HeadphoneManager) {
        self.device = device
        self.manager = manager
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Device Brand Icon, Name, Status & Battery
            HStack(spacing: 8) {
                Image(systemName: device.brand == .huawei ? "headphones" : "headphones.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(device.isConnected ? .accentColor : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(device.isConnected ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                        
                        Text(device.isConnected ? "Connected" : "Disconnected")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if device.isCurrentAudioOutput {
                            Text("• Mac Audio Output")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                Spacer()
                
                BatteryBadgeView(level: device.batteryLevel, isCharging: device.isCharging)
            }
            
            // Section 1: Noise Control (ANC)
            VStack(alignment: .leading, spacing: 4) {
                Text("Noise Control")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                ANCSelectorView(
                    currentMode: device.ancMode,
                    isEnabled: device.isConnected
                ) { newMode in
                    manager.setANCMode(for: device, mode: newMode)
                }
            }
            
            // Section 2: Equalizer / Sound Modes (Bass, Treble, Voices, Default)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Sound Effect")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Spacer()
                    
                    if let eq = device.equalizerPreset {
                        Text(eq.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                }
                
                EqualizerSelectorView(
                    currentPreset: device.equalizerPreset ?? .defaultPreset,
                    isEnabled: device.isConnected
                ) { newPreset in
                    manager.setEqualizer(for: device, preset: newPreset)
                }
            }
            
            // Section 3: Extra Features (Game Mode & Audio Route)
            HStack(spacing: 8) {
                // Game Mode / Low Latency
                let isGameModeOn = device.gameModeEnabled ?? false
                Button(action: {
                    manager.setGameMode(for: device, enabled: !isGameModeOn)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isGameModeOn ? "gamecontroller.fill" : "gamecontroller")
                            .font(.system(size: 11))
                        Text(isGameModeOn ? "Gaming: ON" : "Game Mode")
                            .font(.system(size: 10, weight: isGameModeOn ? .bold : .regular))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(isGameModeOn ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.1))
                    .foregroundColor(isGameModeOn ? .purple : (device.isConnected ? .primary : .secondary.opacity(0.6)))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!device.isConnected)
                
                Spacer()
                
                // Route Audio Button
                if !device.isCurrentAudioOutput && device.isConnected {
                    Button(action: {
                        manager.routeAudioTo(device: device)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "speaker.wave.2.arrow.right.fill")
                                .font(.system(size: 10))
                            Text("Set as Output")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(device.isConnected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
