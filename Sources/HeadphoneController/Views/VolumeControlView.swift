import SwiftUI

public struct VolumeControlView: View {
    @ObservedObject public var audioController: CoreAudioController
    
    public init(audioController: CoreAudioController) {
        self.audioController = audioController
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Mac Volume", systemImage: audioController.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(audioController.currentVolume * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
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
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
}
