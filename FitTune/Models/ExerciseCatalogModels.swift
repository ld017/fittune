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

enum MuscleGroup: String, CaseIterable, Codable, Hashable, Identifiable {
    case chest, back, shoulders, quadriceps, posteriorChain
    case calves, biceps, triceps, forearmsGrip, core

    var id: String { rawValue }
}

enum ExerciseDifficulty: String, CaseIterable, Codable, Hashable {
    case beginner, intermediate, advanced
}

enum Laterality: String, CaseIterable, Codable, Hashable {
    case bilateral, unilateral, alternating
}
