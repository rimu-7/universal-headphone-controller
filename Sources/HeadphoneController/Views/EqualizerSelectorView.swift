import SwiftUI

public struct EqualizerSelectorView: View {
    public let currentPreset: EqualizerPreset?
    public let isEnabled: Bool
    public let onSelectPreset: (EqualizerPreset) -> Void
    
    public init(currentPreset: EqualizerPreset?, isEnabled: Bool = true, onSelectPreset: @escaping (EqualizerPreset) -> Void) {
        self.currentPreset = currentPreset
        self.isEnabled = isEnabled
        self.onSelectPreset = onSelectPreset
    }
    
    public var body: some View {
        HStack(spacing: 3) {
            presetButton(preset: .defaultPreset, title: "Default", icon: "slider.vertical.3")
            presetButton(preset: .bass, title: "Bass Boost", icon: "speaker.wave.3.fill")
            presetButton(preset: .treble, title: "Treble", icon: "waveform")
            presetButton(preset: .voices, title: "Voices", icon: "person.wave.2.fill")
        }
        .padding(3)
        .background(Color.secondary.opacity(0.10))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func presetButton(preset: EqualizerPreset, title: String, icon: String) -> some View {
        let isSelected = (currentPreset == preset)
        Button(action: {
            if isEnabled {
                onSelectPreset(preset)
            }
        }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : (isEnabled ? .primary : .secondary.opacity(0.6)))
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
