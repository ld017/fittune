import Foundation

enum TrainingPhase: String, CaseIterable, Codable, Identifiable, Hashable {
    case primary
    case accessory
    case finisher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary: "主项"
        case .accessory: "辅助项"
        case .finisher: "收尾"
        }
    }
}

