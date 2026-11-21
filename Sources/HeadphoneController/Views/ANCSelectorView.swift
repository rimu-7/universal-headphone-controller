import SwiftUI

public struct ANCSelectorView: View {
    public let currentMode: ANCMode
    public let isEnabled: Bool
    public let onSelectMode: (ANCMode) -> Void
    
    public init(currentMode: ANCMode, isEnabled: Bool = true, onSelectMode: @escaping (ANCMode) -> Void) {
        self.currentMode = currentMode
        self.isEnabled = isEnabled
        self.onSelectMode = onSelectMode
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            modeButton(mode: .cancellation, title: "Noise Cancellation", icon: "ear.and.waveform")
            modeButton(mode: .off, title: "Off", icon: "speaker.slash")
            modeButton(mode: .awareness, title: "Transparency", icon: "waveform")
        }
        .padding(3)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func modeButton(mode: ANCMode, title: String, icon: String) -> some View {
        let isSelected = (currentMode == mode)
        Button(action: {
            if isEnabled {
                onSelectMode(mode)
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : (isEnabled ? .primary : .secondary))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
