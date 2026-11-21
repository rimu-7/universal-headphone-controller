import SwiftUI

public struct BatteryBadgeView: View {
    public let level: Int?
    public let isCharging: Bool
    
    public init(level: Int?, isCharging: Bool = false) {
        self.level = level
        self.isCharging = isCharging
    }
    
    private var batteryColor: Color {
        guard let level = level else { return .secondary }
        if level <= 20 {
            return .red
        } else if level <= 50 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var batteryIconName: String {
        guard let level = level else { return "battery.0" }
        if isCharging {
            return "battery.100.bolt"
        }
        if level <= 10 {
            return "battery.0"
        } else if level <= 30 {
            return "battery.25"
        } else if level <= 60 {
            return "battery.50"
        } else if level <= 85 {
            return "battery.75"
        } else {
            return "battery.100"
        }
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIconName)
                .foregroundColor(batteryColor)
                .font(.system(size: 13, weight: .medium))
            
            if let level = level {
                Text("\(level)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            } else {
                Text("--%")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(6)
    }
}
