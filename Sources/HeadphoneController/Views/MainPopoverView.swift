import SwiftUI

public struct MainPopoverView: View {
    @ObservedObject public var manager: HeadphoneManager
    
    public init(manager: HeadphoneManager = .shared) {
        self.manager = manager
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "headphones")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.accentColor)
                    
                    Text("Headphone Controller")
                        .font(.system(size: 13, weight: .bold))
                }
                
                Spacer()
                
                Button(action: {
                    manager.refreshAll()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh devices and status")
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit Headphone Controller")
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            
            Divider()
            
            // Devices Section
            if manager.devices.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Scanning for paired headphones...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Supports Huawei FreeLace Pro & Edifier Fit900NB")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(manager.devices) { device in
                        DeviceRowView(device: device, manager: manager)
                    }
                }
            }
            
            Divider()
            
            // Mac System Volume
            VolumeControlView(audioController: manager.audioController)
            
            // Footer
            HStack {
                Text("Native macOS • Universal Audio")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
                
                Spacer()
                
                if let active = manager.activeDevice, active.isConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text(active.name)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
        .padding(14)
        .frame(width: 330)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
