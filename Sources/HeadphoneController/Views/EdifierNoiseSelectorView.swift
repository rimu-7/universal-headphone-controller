import SwiftUI

/// Shares Huawei's main noise-control bar, with model-specific ANC choices shown only when needed.
struct EdifierNoiseSelectorView: View {
    let index: UInt8
    let currentValue: UInt8?
    let currentLevel: Int
    let supportsAmbientLevel: Bool
    let isEnabled: Bool
    let preferredCancellationValue: UInt8?
    let onSelect: (UInt8, UInt8?) -> Void

    private var options: [EdifierNoiseOption] { EdifierNoiseOption.options(index: index) }
    private var currentOption: EdifierNoiseOption? { options.first { $0.value == currentValue } }
    private var cancellationOptions: [EdifierNoiseOption] { options.filter { $0.mode == .cancellation } }

    var body: some View {
        VStack(spacing: 6) {
            ANCSelectorView(
                currentMode: currentOption?.mode,
                currentLevel: currentLevel,
                isEnabled: isEnabled && currentOption != nil,
                onSelectMode: selectMode,
                onSelectLevel: ambientAction,
                awarenessTitle: "Ambient"
            )

            if currentOption?.mode == .cancellation && cancellationOptions.count > 1 {
                HStack(spacing: 3) {
                    ForEach(cancellationOptions) { option in
                        cancellationButton(option)
                    }
                }
                .padding(3)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Noise cancellation strength")
            }
        }
    }

    private var ambientAction: ((UInt8) -> Void)? {
        guard supportsAmbientLevel, currentOption?.mode == .awareness else { return nil }
        return { level in
            guard isEnabled, let option = currentOption, (3...9).contains(level), Int(level) != currentLevel else { return }
            onSelect(option.value, level)
        }
    }

    private func selectMode(_ mode: ANCMode) {
        guard isEnabled, currentOption?.mode != mode else { return }
        let option: EdifierNoiseOption?
        if mode == .cancellation {
            option = cancellationOptions.first { $0.value == preferredCancellationValue } ?? cancellationOptions.first
        } else {
            option = options.first { $0.mode == mode }
        }
        guard let option else { return }
        onSelect(option.value, nil)
    }

    private func cancellationButton(_ option: EdifierNoiseOption) -> some View {
        let selected = currentValue == option.value
        let title = option.title == "Wind Reduction" ? "Wind" : option.title.replacingOccurrences(of: " Cancellation", with: "")
        return Button {
            guard isEnabled, !selected else { return }
            onSelect(option.value, nil)
        } label: {
            Text(title)
                .font(.system(size: 10, weight: selected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .padding(.horizontal, 3)
                .background(selected ? Color.accentColor.opacity(0.16) : Color.clear)
                .foregroundColor(selected ? .primary : .secondary)
                .cornerRadius(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(option.title)
        .accessibilityLabel(option.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
