import SwiftUI

public struct VolumeControlView: View {
    @ObservedObject public var audioController: CoreAudioController
    
    public init(audioController: CoreAudioController) {
        self.audioController = audioController
    }
    
    private var volumeIcon: String {
        if audioController.isMuted || audioController.currentVolume == 0 {
            return "speaker.slash.fill"
        } else if audioController.currentVolume < 0.33 {
            return "speaker.wave.1.fill"
        } else if audioController.currentVolume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Mac Volume", systemImage: volumeIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Text("\(Int(round(audioController.currentVolume * 100)))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(audioController.isMuted ? .red : .primary)
            }
            
            HStack(spacing: 8) {
                Button(action: {
                    audioController.setMuted(!audioController.isMuted)
                }) {
                    Image(systemName: audioController.isMuted ? "speaker.slash.circle.fill" : "speaker.slash.circle")
                        .font(.system(size: 16))
                        .foregroundColor(audioController.isMuted ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help(audioController.isMuted ? "Unmute" : "Mute")
                
                Slider(
                    value: Binding(
                        get: { Double(audioController.currentVolume) },
                        set: { audioController.setVolume(Float($0)) }
                    ),
                    in: 0.0...1.0
                )
                .accentColor(.accentColor)
                
                Image(systemName: "speaker.wave.3")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
}
