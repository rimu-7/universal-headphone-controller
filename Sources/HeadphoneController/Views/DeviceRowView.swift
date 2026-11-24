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
            HStack(spacing: 8) {
                Image(systemName: device.brand.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(device.isConnected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .help(device.name)
                    Text(device.isCurrentAudioOutput ? "Mac Audio Output" : (device.isConnected ? "Connected" : "Disconnected"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                BatteryBadgeView(level: device.batteryLevel, isCharging: device.isCharging)
            }

            if device.brand == .edifier {
                if device.controlState != .ready {
                    HStack(alignment: .top, spacing: 6) {
                        if [.connecting, .discovering, .probing, .searching].contains(device.controlState) {
                            ProgressView().controlSize(.mini)
                        }
                        Text(device.controlState.message)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !device.pendingFeatures.subtracting([.noiseControl]).isEmpty {
                    Text("Waiting for headset confirmation…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Setting change pending. Waiting for headset confirmation.")
                }
                if let error = device.controlError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if device.brand == .huawei || device.supportedFeatures.contains(.noiseControl) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        sectionLabel("Noise Control")
                        Spacer()
                        if device.brand == .edifier && device.pendingFeatures.contains(.noiseControl) {
                            ProgressView().controlSize(.mini)
                            Text("Applying…")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .accessibilityLabel("Waiting for headset to confirm noise mode")
                        }
                    }
                    if let index = device.edifierANCIndex {
                        EdifierNoiseSelectorView(
                            index: index,
                            currentValue: device.hasANCState ? device.edifierNoiseValue : nil,
                            currentLevel: device.ancLevel,
                            supportsAmbientLevel: device.supportedFeatures.contains(.ambientLevel),
                            isEnabled: device.canControl(.noiseControl),
                            preferredCancellationValue: device.edifierCancellationSelection?.index == index ? device.edifierCancellationSelection?.value : nil
                        ) { value, level in
                            manager.setEdifierNoise(for: device, value: value, level: level)
                        }
                    } else {
                        ANCSelectorView(
                            currentMode: device.brand == .huawei || device.hasANCState ? device.ancMode : nil,
                            currentLevel: device.ancLevel,
                            isEnabled: device.canControl(.noiseControl),
                            onSelectMode: { manager.setANCMode(for: device, mode: $0) },
                            onSelectLevel: ambientAction
                        )
                    }
                }
            }

            if device.brand == .huawei || device.supportedFeatures.contains(.equalizer) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Sound Effect")
                    EqualizerSelectorView(
                        currentPreset: device.equalizerPreset,
                        isEnabled: device.canControl(.equalizer),
                        edifierProfile: device.brand == .edifier ? device.edifierProfile : nil
                    ) { manager.setEqualizer(for: device, preset: $0) }
                }
            }

            if device.supportedFeatures.contains(.sceneMode) {
                Picker("Scene", selection: Binding(
                    get: { device.edifierScene ?? .music },
                    set: { manager.setEdifierScene(for: device, scene: $0) }
                )) {
                    ForEach(EdifierScene.allCases) { scene in Text(scene.title).tag(scene) }
                }
                .pickerStyle(.segmented)
                .disabled(!device.canControl(.sceneMode))
                .accessibilityLabel("Music, Game or Spatial sound")
            }

            HStack(spacing: 8) {
                if device.brand == .huawei || (device.supportedFeatures.contains(.gameMode) && !device.supportedFeatures.contains(.sceneMode)) {
                    let enabled = device.gameModeEnabled ?? false
                    Button {
                        manager.setGameMode(for: device, enabled: !enabled)
                    } label: {
                        Label(enabled ? "Gaming: On" : "Game Mode", systemImage: "gamecontroller")
                    }
                    .disabled(!device.canControl(.gameMode))
                }
                Spacer()
                if !device.isCurrentAudioOutput && device.isConnected {
                    Button("Set as Output") { manager.routeAudioTo(device: device) }
                }
            }
            .controlSize(.small)

            if device.brand == .edifier {
                HStack {
                    Button("Retry Controls") { manager.retryControls(for: device) }
                        .disabled([.connecting, .discovering, .probing].contains(device.controlState))
                    Spacer()
                    Button("Copy Diagnostics") { manager.copyDiagnostics(for: device) }
                        .help("Copy model, services and recent protocol responses for troubleshooting")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(device.isConnected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private var ambientAction: ((UInt8) -> Void)? {
        guard device.brand == .edifier, device.supportedFeatures.contains(.ambientLevel) else { return nil }
        return { manager.setANCMode(for: device, mode: .awareness, ambientLevel: $0) }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
    }
}
