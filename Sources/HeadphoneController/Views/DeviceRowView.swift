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
            // Top Row: Device Info & Battery
            HStack(spacing: 8) {
                Image(systemName: device.brand == .huawei ? "headphones" : "headphones.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(device.isConnected ? .accentColor : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(device.isConnected ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                        
                        Text(device.isConnected ? "Connected" : "Disconnected")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if device.isCurrentAudioOutput {
                            Text("• Audio Output")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                Spacer()
                
                BatteryBadgeView(level: device.batteryLevel, isCharging: device.isCharging)
            }
            
            // Middle: ANC Mode Switcher
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
            
            // Bottom Row: Extra Features & Audio Route Button
            HStack(spacing: 8) {
                // Audio Route Button
                if !device.isCurrentAudioOutput && device.isConnected {
                    Button(action: {
                        manager.routeAudioTo(device: device)
                    }) {
                        Label("Route Audio", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                // Game Mode / Low Latency
                if let gameMode = device.gameModeEnabled {
                    Button(action: {
                        manager.setGameMode(for: device, enabled: !gameMode)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "gamecontroller.fill")
                            Text("Game Mode")
                        }
                        .font(.system(size: 11, weight: gameMode ? .semibold : .regular))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(gameMode ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.1))
                        .foregroundColor(gameMode ? .purple : .secondary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!device.isConnected)
                } else if device.brand == .huawei && device.isConnected {
                    Button(action: {
                        manager.setGameMode(for: device, enabled: true)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "gamecontroller")
                            Text("Low Latency")
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .foregroundColor(.secondary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Equalizer preset menu for Huawei
                if device.brand == .huawei && device.isConnected {
                    Menu {
                        ForEach(EqualizerPreset.allCases) { preset in
                            Button(action: {
                                manager.setEqualizer(for: device, preset: preset)
                            }) {
                                HStack {
                                    Text(preset.title)
                                    if device.equalizerPreset == preset {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.vertical.3")
                            Text(device.equalizerPreset?.title ?? "EQ")
                        }
                        .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 90)
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
