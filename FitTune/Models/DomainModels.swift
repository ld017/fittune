import Foundation

enum TrainingGoal: String, CaseIterable, Codable, Identifiable {
    case fatLoss
    case hypertrophy
    case recomposition
    case strength
    case generalFitness
    case returnToTraining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fatLoss: "减脂保肌"
        case .hypertrophy: "增肌"
        case .recomposition: "身体重组"
        case .strength: "最大力量"
        case .generalFitness: "健康体能"
        case .returnToTraining: "恢复训练"
        }
    }

    var subtitle: String {
        switch self {
        case .fatLoss: "在热量缺口中尽量保留肌肉与力量"
        case .hypertrophy: "提高有效训练量，促进肌肉增长"
        case .recomposition: "稳步增肌，同时改善体脂与围度"
        case .strength: "优先提升目标动作的最大力量"
        case .generalFitness: "建立均衡、可持续的全身训练习惯"
        case .returnToTraining: "停训后以较低疲劳安全恢复"
        }
    }

    var symbol: String {
        switch self {
        case .fatLoss: "flame.fill"
        case .hypertrophy: "figure.strengthtraining.traditional"
        case .recomposition: "arrow.triangle.2.circlepath"
        case .strength: "bolt.fill"
        case .generalFitness: "heart.fill"
        case .returnToTraining: "arrow.uturn.backward.circle.fill"
        }
    }
}

enum SecondaryGoal: String, CaseIterable, Codable, Identifiable {
    case none
    case strength
    case hypertrophy
    case cardio
    case mobility
    case timeEfficiency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "无次目标"
        case .strength: "兼顾力量"
        case .hypertrophy: "兼顾增肌"
        case .cardio: "兼顾心肺"
        case .mobility: "改善灵活性"
        case .timeEfficiency: "时间效率"
        }
    }
}

enum ExperienceLevel: String, CaseIterable, Codable, Identifiable {
    case new
    case beginner
    case intermediate
    case advanced
    case returning
    case autoAssess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: "完全新手"
        case .beginner: "初级"
        case .intermediate: "中级"
        case .advanced: "高级"
        case .returning: "停训后恢复"
        case .autoAssess: "由 App 评估"
        }
    }

    var subtitle: String {
        switch self {
        case .new: "几乎没有系统抗阻训练经历"
        case .beginner: "能独立训练，系统训练不足约一年"
        case .intermediate: "需要按周或训练块才能持续进步"
        case .advanced: "多年稳定训练，专项需求明确"
        case .returning: "有经验，但近期中断数周或更久"
        case .autoAssess: "通过前 2–3 次训练逐步校准"
        }
    }

    var symbol: String {
        switch self {
        case .new: "leaf.fill"
        case .beginner: "figure.walk"
        case .intermediate: "figure.run"
        case .advanced: "trophy.fill"
        case .returning: "clock.arrow.circlepath"
        case .autoAssess: "wand.and.stars"
        }
    }
}

enum EquipmentProfile: String, CaseIterable, Codable, Identifiable {
    case fullGym
    case dumbbells
    case bodyweightBands

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullGym: "完整健身房"
        case .dumbbells: "哑铃与训练凳"
        case .bodyweightBands: "徒手与弹力带"
        }
    }

    var symbol: String {
        switch self {
        case .fullGym: "dumbbell.fill"
        case .dumbbells: "scalemass.fill"
        case .bodyweightBands: "figure.core.training"
        }
    }
}

enum TrainingSplit: String, CaseIterable, Codable, Identifiable {
    case automatic
    case fullBody
    case upperLower
    case pushPullLegs
    case chestBackShouldersLegs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "智能安排"
        case .fullBody: "全身训练"
        case .upperLower: "上肢 / 下肢"
        case .pushPullLegs: "推 / 拉 / 腿三分化"
        case .chestBackShouldersLegs: "胸 / 背 / 肩 / 腿四分化"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic: "根据每周天数与经验选择"
        case .fullBody: "每次覆盖主要动作模式，适合每周 2–3 天"
        case .upperLower: "上下肢交替，适合每周 3–4 天"
        case .pushPullLegs: "按推、拉、腿轮换，适合每周 3–6 天"
        case .chestBackShouldersLegs: "按部位组织，适合偏好四分化的人"
        }
    }
}

enum TodayTrainingIntent: String, Codable {
    case undecided
    case train
    case rest

    var title: String {
        switch self {
        case .undecided: "未决定"
        case .train: "今天训练"
        case .rest: "今天休息"
        }
    }
}

enum BodyRegion: String, CaseIterable, Codable, Identifiable, Hashable {
    case chest
    case back
    case shoulders
    case legs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: "胸"
        case .back: "背"
        case .shoulders: "肩"
        case .legs: "腿"
        }
    }
}

enum DailyTrainingFocus: String, CaseIterable, Codable, Identifiable {
    case recommended
    case chest
    case back
    case shoulders
    case legs
    case push
    case pull
    case fullBody

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: "按计划推荐"
        case .chest: "胸"
        case .back: "背"
        case .shoulders: "肩"
        case .legs: "腿"
        case .push: "推"
        case .pull: "拉"
        case .fullBody: "全身"
        }
    }

    var symbol: String {
        switch self {
        case .recommended: "sparkles"
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.rower"
        case .shoulders: "figure.arms.open"
        case .legs: "figure.run"
        case .push: "arrow.up.forward"
        case .pull: "arrow.down.backward"
        case .fullBody: "figure.mixed.cardio"
        }
    }

    var primaryRegion: BodyRegion? {
        switch self {
        case .chest: .chest
        case .back, .pull: .back
        case .shoulders: .shoulders
        case .legs: .legs
        case .recommended, .push, .fullBody: nil
        }
    }
}

struct DailyTrainingChoice: Codable, Equatable {
    var date: Date = .now
    var intent: TodayTrainingIntent = .undecided
    var focus: DailyTrainingFocus = .recommended
    var avoidedRegions: Set<BodyRegion> = []
}

enum StrengthTrainingGoal: String, CaseIterable, Codable, Identifiable {
    case balanced
    case hypertrophy
    case maxStrength

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "均衡力量"
        case .hypertrophy: "增肌"
        case .maxStrength: "最大力量"
        }
    }
}

enum CardioTrainingGoal: String, CaseIterable, Codable, Identifiable {
    case none
    case fatLoss
    case aerobicBase
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "暂不安排"
        case .fatLoss: "减脂与消耗"
        case .aerobicBase: "基础有氧能力"
        case .performance: "提升心肺表现"
        }
    }
}

enum EquipmentKind: String, CaseIterable, Codable, Identifiable {
    case barbell
    case dumbbell
    case machineCable
    case smithMachine
    case selectorizedMachine
    case cable
    case bodyweightBand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .barbell: "杠铃"
        case .dumbbell: "哑铃"
        case .machineCable: "固定器械 / 绳索"
        case .smithMachine: "史密斯机"
        case .selectorizedMachine: "固定器械"
        case .cable: "绳索"
        case .bodyweightBand: "徒手 / 弹力带"
        }
    }
}

enum BiologicalSex: String, CaseIterable, Codable, Identifiable {
    case notSet
    case female
    case male

    var id: String { rawValue }
    var title: String {
        switch self {
        case .notSet: "未设置"
        case .female: "女性"
        case .male: "男性"
        }
    }
}

struct UserProfile: Codable, Equatable {
    var nickname: String
    var goal: TrainingGoal
    var secondaryGoal: SecondaryGoal
    var experience: ExperienceLevel
    var weeklyDays: Int
    var sessionMinutes: Int
    var equipment: EquipmentProfile
    var bodyWeightKg: Double
    var loadIncrementKg: Double
    var splitPreference: TrainingSplit? = nil
    var strengthTrainingGoal: StrengthTrainingGoal? = nil
    var cardioTrainingGoal: CardioTrainingGoal? = nil
    var ageYears: Int? = nil
    var heightCm: Double? = nil
    var biologicalSex: BiologicalSex? = nil
    var bodyFatPercent: Double? = nil
    var leanMassKg: Double? = nil
    var measuredRMRKcal: Double? = nil
    var restingHeartRate: Double? = nil
    var measuredMaxHeartRate: Double? = nil
}

struct ReadinessInput: Codable, Equatable {
    var date: Date = .now
    var sleepHours: Double = 7.5
    var soreness: Int = 2
    var stress: Int = 2
    var motivation: Int = 4
    var sleepQuality: Int? = nil
}

enum ReadinessLevel: String, Codable {
    case ready
    case moderate
    case low

    var title: String {
        switch self {
        case .ready: "状态良好"
        case .moderate: "建议保守"
        case .low: "优先恢复"
        }
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .moderate: "gauge.with.dots.needle.50percent"
        case .low: "moon.zzz.fill"
        }
    }
}

struct ReadinessAssessment: Equatable {
    var score: Int
    var level: ReadinessLevel
    var summary: String
    var loadMultiplier: Double
    var setReduction: Int
}

enum MovementPattern: String, CaseIterable, Codable, Identifiable {
    case squat
    case hinge
    case horizontalPush
    case horizontalPull
    case verticalPush
    case verticalPull
    case singleLeg
    case arms
    case core
    case chestIsolation
    case shoulderIsolation
    case kneeFlexion
    case calves
    case conditioning

    var id: String { rawValue }
    var title: String {
        switch self {
        case .squat: "深蹲 / 股四头"
        case .hinge: "髋铰链 / 臀后链"
        case .horizontalPush: "水平推 / 胸"
        case .horizontalPull: "水平拉 / 背"
        case .verticalPush: "垂直推 / 肩"
        case .verticalPull: "垂直拉 / 背"
        case .singleLeg: "单腿训练"
        case .arms: "手臂"
        case .core: "核心"
        case .chestIsolation: "胸部孤立"
        case .shoulderIsolation: "肩部孤立"
        case .kneeFlexion: "腿后侧屈膝"
        case .calves: "小腿"
        case .conditioning: "体能"
        }
    }
}

struct ExerciseOption: Identifiable, Hashable {
    var name: String
    var pattern: MovementPattern
    var equipment: EquipmentKind
    var category: ExerciseCategory? = nil

    var id: String { "\(pattern.rawValue)-\(name)" }
    var resolvedCategory: ExerciseCategory { category ?? ExerciseCategory(pattern: pattern) }
}

enum ExerciseCategory: String, CaseIterable, Codable, Identifiable {
    case chest, back, shoulders, quadriceps, posteriorChain, arms, core, calves, conditioning

    var id: String { rawValue }
    var title: String {
        switch self {
        case .chest: "胸"
        case .back: "背"
        case .shoulders: "肩"
        case .quadriceps: "腿 · 股四头"
        case .posteriorChain: "腿 · 臀腿后侧"
        case .arms: "手臂"
        case .core: "核心"
        case .calves: "小腿"
        case .conditioning: "体能"
        }
    }

    init(pattern: MovementPattern) {
        switch pattern {
        case .horizontalPush, .chestIsolation: self = .chest
        case .horizontalPull, .verticalPull: self = .back
        case .verticalPush, .shoulderIsolation: self = .shoulders
        case .squat, .singleLeg: self = .quadriceps
        case .hinge, .kneeFlexion: self = .posteriorChain
        case .arms: self = .arms
        case .core: self = .core
        case .calves: self = .calves
        case .conditioning: self = .conditioning
        }
    }
}

struct ExercisePrescription: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var pattern: MovementPattern
    var sets: Int
    var repLower: Int
    var repUpper: Int
    var targetRIR: Int
    var isPriority: Bool
    var suggestedLoadKg: Double?
    var equipmentKind: EquipmentKind? = nil
    var suggestedLoadReason: String? = nil

    var targetText: String {
        "\(sets) 组 × \(repLower)–\(repUpper) 次 · \(targetRIR) RIR"
    }
}

enum CardioIntensity: String, CaseIterable, Codable, Identifiable {
    case recovery
    case zone2
    case intervals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery: "轻松恢复"
        case .zone2: "低至中等强度"
        case .intervals: "间歇训练"
        }
    }
}

enum CardioModality: String, CaseIterable, Codable, Identifiable {
    case inclineWalking
    case stairClimber
    case swimming
    case running
    case cycling
    case rowing
    case elliptical
    case briskWalking
    case jumpRope

    var id: String { rawValue }
    var title: String {
        switch self {
        case .inclineWalking: "爬坡走"
        case .stairClimber: "爬楼梯 / 登阶机"
        case .swimming: "游泳"
        case .running: "跑步"
        case .cycling: "骑行 / 动感单车"
        case .rowing: "划船机"
        case .elliptical: "椭圆机"
        case .briskWalking: "快走"
        case .jumpRope: "跳绳"
        }
    }
    var symbol: String {
        switch self {
        case .inclineWalking, .briskWalking: "figure.walk"
        case .stairClimber: "figure.stair.stepper"
        case .swimming: "figure.pool.swim"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .jumpRope: "figure.jumprope"
        }
    }
}

struct CardioSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var modality: String
    var minutes: Int
    var intensity: CardioIntensity
    var guidance: String
}

struct TrainingSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var focus: String
    var exercises: [ExercisePrescription]

    var estimatedMinutes: Int {
        max(25, exercises.reduce(0) { $0 + $1.sets * ($1.isPriority ? 4 : 3) })
    }
}

struct TrainingPlan: Codable, Equatable {
    var title: String
    var rationale: String
    var sessions: [TrainingSession]
    var generatedAt: Date
    var ruleVersion: String
    var cardioSessions: [CardioSession]? = nil
}

enum SetKind: String, Codable, Equatable {
    case warmup
    case working
}

struct SetResult: Identifiable, Codable, Equatable {
    var id = UUID()
    var exerciseID: UUID
    var exerciseName: String
    var setNumber: Int
    var loadKg: Double
    var reps: Int
    var rir: Int
    var completedAt: Date = .now
    var movementPattern: MovementPattern? = nil
    var techniqueQuality: Int? = nil
    var feeling: SetFeeling? = nil
    var setKind: SetKind? = nil

    var resolvedSetKind: SetKind { setKind ?? .working }
}

enum SetFeeling: String, CaseIterable, Codable, Identifiable {
    case veryEasy
    case easy
    case moderate
    case hard
    case veryHard
    case maximal
    case techniqueBreakdown
    case pain
    // Kept for decoding v0.4 records.
    case good
    case exhausted

    var id: String { rawValue }
    static let currentCases: [SetFeeling] = [.veryEasy, .easy, .moderate, .hard, .veryHard, .maximal, .techniqueBreakdown, .pain]
    var title: String {
        switch self {
        case .veryEasy: "RPE 5–6 · 很轻松（RIR ≥4）"
        case .easy: "RPE 7 · 稳定（约 RIR 3）"
        case .moderate, .good: "RPE 8 · 较难（约 RIR 2）"
        case .hard: "RPE 9 · 很难（约 RIR 1）"
        case .veryHard: "RPE 9.5 · 几乎力竭"
        case .maximal, .exhausted: "RPE 10 · 已力竭"
        case .techniqueBreakdown: "动作变形 · 技术性停止"
        case .pain: "疼痛 / 异常不适 · 立即停止"
        }
    }
    var symbol: String {
        switch self {
        case .veryEasy, .easy: "face.smiling"
        case .moderate, .good: "checkmark.circle"
        case .hard, .veryHard: "flame"
        case .maximal, .exhausted, .techniqueBreakdown, .pain: "exclamationmark.triangle"
        }
    }

    var rpe: Double {
        switch self {
        case .veryEasy: 5.5
        case .easy: 7
        case .moderate, .good: 8
        case .hard: 9
        case .veryHard: 9.5
        case .maximal, .exhausted, .techniqueBreakdown, .pain: 10
        }
    }

    var requiresStop: Bool { self == .pain || self == .techniqueBreakdown }
}

struct TrainingEffect: Identifiable, Codable, Equatable {
    var id = UUID()
    var strengthScore: Int
    var hypertrophyScore: Int
    var aerobicScore: Int
    var fatigueScore: Int
    var estimatedRecoveryHours: Int
    var summary: String
    var advice: String
    var recoveryLowerHours: Int? = nil
    var recoveryUpperHours: Int? = nil
    var confidence: String? = nil
    var trainingLoadAU: Double? = nil
    var method: String? = nil
}

enum WorkoutCompletionStatus: String, Codable {
    case completed
    case partial

    var title: String {
        switch self {
        case .completed: "完整完成"
        case .partial: "部分完成"
        }
    }
}

struct WorkoutRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var sessionName: String
    var startedAt: Date
    var completedAt: Date
    var readinessScore: Int
    var sets: [SetResult]
    var sessionQuality: Int? = nil
    var completionStatus: WorkoutCompletionStatus? = nil
    var activeEnergyKcal: Double? = nil
    var effect: TrainingEffect? = nil
    var sessionRPE: Double? = nil
    var averageHeartRate: Double? = nil
    var measuredActiveEnergyKcal: Double? = nil
    var energyMethod: String? = nil
    var energyLowerBoundKcal: Double? = nil
    var energyUpperBoundKcal: Double? = nil
    var externalID: String? = nil

    var resolvedCompletionStatus: WorkoutCompletionStatus {
        completionStatus ?? .completed
    }
}

struct WearableStrengthWorkout: Equatable {
    var date: Date
    var durationMinutes: Int
    var activeEnergyKcal: Double?
    var averageHeartRate: Double?
    var externalID: String
}

struct CardioWorkoutRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var modality: CardioModality
    var intensity: CardioIntensity
    var durationMinutes: Int
    var distanceKm: Double? = nil
    var averageHeartRate: Double? = nil
    var activeEnergyKcal: Double
    var source: String
    var externalID: String? = nil
    var effect: TrainingEffect? = nil
    var speedKph: Double? = nil
    var inclinePercent: Double? = nil
    var powerWatts: Double? = nil
    var floorsClimbed: Double? = nil
    var sessionRPE: Double? = nil
    var energyMethod: String? = nil
    var energyLowerBoundKcal: Double? = nil
    var energyUpperBoundKcal: Double? = nil
}

struct BodyCompositionEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var weightKg: Double
    var bodyFatPercent: Double? = nil
    var leanMassKg: Double? = nil
    var waistCm: Double? = nil
    var source: String
}

struct EnergyEstimate: Equatable {
    var kilocalories: Double
    var lowerBound: Double
    var upperBound: Double
    var method: String
    var confidence: String
}

struct DailyActiveEnergyEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var kilocalories: Double
    var source: String
}

struct DailyStepEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var steps: Int
    var distanceKm: Double? = nil
    var estimatedActiveEnergyKcal: Double
    var source: String
}

struct WeightEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var kilograms: Double
    var source: String
}

enum CardioMetricType: String, CaseIterable, Codable, Identifiable {
    case twelveMinuteDistance
    case vo2Max
    case restingHeartRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twelveMinuteDistance: "12 分钟跑 / 走距离"
        case .vo2Max: "VO₂ max"
        case .restingHeartRate: "静息心率"
        }
    }

    var unit: String {
        switch self {
        case .twelveMinuteDistance: "m"
        case .vo2Max: "ml/kg/min"
        case .restingHeartRate: "bpm"
        }
    }

    var higherIsBetter: Bool { self != .restingHeartRate }
}

struct CardioMetricEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var type: CardioMetricType
    var value: Double
    var source: String
}

struct RecoveryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var sleepHours: Double
    var sleepQuality: Int
    var soreness: Int
    var stress: Int
    var motivation: Int
    var readinessScore: Int
}

enum LoadAdjustment: String, Codable, Equatable {
    case increase
    case hold
    case decrease

    var title: String {
        switch self {
        case .increase: "小幅加重"
        case .hold: "保持重量"
        case .decrease: "降低重量"
        }
    }

    var symbol: String {
        switch self {
        case .increase: "arrow.up.right"
        case .hold: "equal"
        case .decrease: "arrow.down.right"
        }
    }
}

struct SetRecommendation: Codable, Equatable {
    var nextLoadKg: Double
    var adjustment: LoadAdjustment
    var reason: String
    var confidence: String
    var restSeconds: Int
    var suggestedRemainingSets: Int
    var continuation: TrainingContinuation
}

enum TrainingContinuation: String, Codable, Equatable {
    case continueTraining
    case stopExercise
    case stopWorkout

    var title: String {
        switch self {
        case .continueTraining: "可以继续"
        case .stopExercise: "建议结束本动作"
        case .stopWorkout: "建议结束本次训练"
        }
    }
}

enum WorkoutDraftPhase: String, Codable, Equatable {
    case training
    case resting
    case exerciseComplete
}

struct RestRecommendation: Codable, Equatable {
    var lowerSeconds: Int
    var recommendedSeconds: Int
    var upperSeconds: Int
    var confidence: String
    var reasons: [String]
    var inputsUsed: [String]
}

struct WorkoutDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var sourceSessionID: UUID
    var session: TrainingSession
    var startedAt: Date = .now
    var updatedAt: Date = .now
    var exerciseIndex: Int
    var setNumber: Int
    var warmupSetsByExercise: [UUID: Int] = [:]
    var loadKg: Double
    var reps: Int
    var rir: Int
    var techniqueQuality: Int
    var hasPain: Bool
    var averageHeartRate = 0.0
    var measuredActiveEnergyKcal = 0.0
    var results: [SetResult] = []
    var recommendation: SetRecommendation? = nil
    var restRecommendation: RestRecommendation? = nil
    var restStartedAt: Date? = nil
    var phase: WorkoutDraftPhase = .training
    var userOverrodeSuggestedLoad = false

    var currentExercise: ExercisePrescription { session.exercises[exerciseIndex] }

    var currentWarmupSets: Int {
        min(currentExercise.sets, max(0, warmupSetsByExercise[currentExercise.id] ?? 0))
    }

    var currentSetKind: SetKind {
        setNumber <= currentWarmupSets ? .warmup : .working
    }

    var workingSetOrdinal: Int {
        max(0, setNumber - currentWarmupSets)
    }

    var totalWorkingSets: Int {
        max(0, currentExercise.sets - currentWarmupSets)
    }
}

struct DailyEnergySummary: Equatable {
    var restingKcal: Double?
    var strengthKcal: Double
    var cardioKcal: Double
    var walkingStepsKcal: Double
    var steps: Int
    var otherWearableKcal: Double

    var totalKcal: Double? {
        restingKcal.map { $0 + strengthKcal + cardioKcal + walkingStepsKcal + otherWearableKcal }
    }
}

struct StartingLoadRecommendation: Equatable {
    var loadKg: Double?
    var adjustment: LoadAdjustment
    var reason: String
    var confidence: String
    var daysSinceLast: Int?

    var displayLoad: String {
        guard let loadKg else { return "待校准" }
        return loadKg == 0 ? "徒手 / 弹力带" : "\(loadKg.formatted(.number.precision(.fractionLength(1)))) kg"
    }
}

struct AppSnapshot: Codable {
    var profile: UserProfile?
    var plan: TrainingPlan?
    var readiness: ReadinessInput
    var workoutHistory: [WorkoutRecord]
    var weightHistory: [WeightEntry]
    var cardioHistory: [CardioMetricEntry]? = nil
    var recoveryHistory: [RecoveryEntry]? = nil
    var dailyTrainingChoice: DailyTrainingChoice? = nil
    var cardioWorkouts: [CardioWorkoutRecord]? = nil
    var dailyActiveEnergy: [DailyActiveEnergyEntry]? = nil
    var dailySteps: [DailyStepEntry]? = nil
    var bodyCompositionHistory: [BodyCompositionEntry]? = nil
    var deletedWorkoutHistory: [WorkoutRecord]? = nil
    var deletedCardioWorkouts: [CardioWorkoutRecord]? = nil
    var deletedWeightHistory: [WeightEntry]? = nil
    var deletedCardioHistory: [CardioMetricEntry]? = nil
    var deletedRecoveryHistory: [RecoveryEntry]? = nil
    var deletedBodyCompositionHistory: [BodyCompositionEntry]? = nil
    var activeWorkoutDraft: WorkoutDraft? = nil
}
