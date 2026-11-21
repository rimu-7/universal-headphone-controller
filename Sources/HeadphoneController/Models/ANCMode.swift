import Foundation

public enum ANCMode: Int, CaseIterable, Identifiable, Codable {
    case off = 0
    case cancellation = 1
    case awareness = 2
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .cancellation:
            return "Noise Cancellation"
        case .off:
            return "Off"
        case .awareness:
            return "Awareness"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .cancellation:
            return "ANC"
        case .off:
            return "Off"
        case .awareness:
            return "Ambient"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .cancellation:
            return "ear.and.waveform"
        case .off:
            return "speaker.slash"
        case .awareness:
            return "waveform"
        }
    }
}
