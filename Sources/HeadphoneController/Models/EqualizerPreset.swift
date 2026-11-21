import Foundation

public enum EqualizerPreset: Int, CaseIterable, Identifiable, Codable {
    case defaultPreset = 1
    case bass = 2
    case treble = 3
    case voices = 9
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .defaultPreset:
            return "Default"
        case .bass:
            return "Bass Boost"
        case .treble:
            return "Treble Boost"
        case .voices:
            return "Vocal Boost"
        }
    }
}
