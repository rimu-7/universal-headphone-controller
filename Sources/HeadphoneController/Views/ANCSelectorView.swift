import SwiftUI

public struct ANCSelectorView: View {
    public let currentMode: ANCMode?
    public let currentLevel: Int
    public let isEnabled: Bool
    public let onSelectMode: (ANCMode) -> Void
    public let onSelectLevel: ((UInt8) -> Void)?
    public let awarenessTitle: String

    public init(
        currentMode: ANCMode?,
        currentLevel: Int = 8,
        isEnabled: Bool = true,
        onSelectMode: @escaping (ANCMode) -> Void,
        onSelectLevel: ((UInt8) -> Void)? = nil,
        awarenessTitle: String = "Transparency"
    ) {
        self.currentMode = currentMode
        self.currentLevel = currentLevel
        self.isEnabled = isEnabled
        self.onSelectMode = onSelectMode
        self.onSelectLevel = onSelectLevel
        self.awarenessTitle = awarenessTitle
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Main 3-way ANC Switcher
            HStack(spacing: 4) {
                modeButton(
                    mode: .cancellation,
                    title: "ANC",
                    icon: "ear.and.waveform",
                    selectedBg: Color.blue
                )
                modeButton(
                    mode: .off,
                    title: "Off",
                    icon: "speaker.slash",
                    selectedBg: Color.secondary.opacity(0.4)
                )
                modeButton(
                    mode: .awareness,
                    title: awarenessTitle,
                    icon: "waveform",
                    selectedBg: Color.teal
                )
            }
            .padding(3)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(8)

            // Transparency Level Controls (Appears when Transparency is active)
            if currentMode == .awareness && onSelectLevel != nil {
                HStack(spacing: 3) {
                    Text("Ambient (dB):")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.trailing, 2)

                    ForEach(3...9, id: \.self) { level in
                        levelButton(level: UInt8(level), label: level > 6 ? "+\(level - 6)" : "\(level - 6)")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.teal.opacity(0.10))
                .cornerRadius(6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func modeButton(mode: ANCMode, title: String, icon: String, selectedBg: Color) -> some View {
        let isSelected = (currentMode == mode)
        Button(action: {
            if isEnabled {
                withAnimation(.easeInOut(duration: 0.15)) {
                    onSelectMode(mode)
                }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(isSelected ? selectedBg : Color.clear)
            .foregroundColor(isSelected ? .white : (isEnabled ? .primary : .secondary.opacity(0.5)))
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(mode.title)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private func levelButton(level: UInt8, label: String) -> some View {
        let isSelected = (currentLevel == Int(level))
        Button(action: {
            if isEnabled {
                onSelectLevel?(level)
            }
        }) {
            Text(label)
                .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(isSelected ? Color.teal : Color.secondary.opacity(0.12))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Ambient level \(label) decibels")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
