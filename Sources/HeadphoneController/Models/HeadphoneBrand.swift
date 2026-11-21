import Foundation

public enum HeadphoneBrand: String, CaseIterable, Identifiable, Codable {
    case huawei = "Huawei"
    case edifier = "Edifier"
    case generic = "Bluetooth Audio"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .huawei:
            return "headphones"
        case .edifier:
            return "headphones.circle.fill"
        case .generic:
            return "speaker.wave.2"
        }
    }
}
