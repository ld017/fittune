import Foundation

struct LiveHeartRateSignal: Equatable {
    var response: SetHeartRateResponse?
    var personalComparison: PersonalRecoveryComparison
    var sourceName: String
    var currentHeartRate: Double? = nil
}

enum AdaptationConfidence: String, Equatable {
    case calibrating
    case measured
    case estimated
}

struct LiveAdaptationAdvice: Equatable {
    var nextLoadKg: Double
    var adjustment: LoadAdjustment
    var rest: RestRecommendation
    var confidence: AdaptationConfidence
    var reasons: [String]
    var safetyAlerts: [String]
    var usedLiveHeartRate: Bool
    var canContinue: Bool
    var automaticallyEndsExercise: Bool
}

enum LiveAdaptationEngine {
    private static let dynamicReasonPrefixes = [
        "实时心率",
        "个人心率恢复"
    ]

    static func adapt(
        baseRecommendation: SetRecommendation,
        baseRest: RestRecommendation,
        currentLoadKg: Double,
        liveSignal: LiveHeartRateSignal?,
        calibrationPairs: Int,
        hasPain: Bool,
        painAlertThresholdReached: Bool,
        maximumHeartRateAlert: Int?
    ) -> LiveAdaptationAdvice {
        var nextLoad = baseRecommendation.nextLoadKg
        var adjustment = baseRecommendation.adjustment
        var rest = baseRest
        var reasons = normalizedBaseReasons(baseRecommendation.reason)
        var alerts: [String] = []
        rest.reasons.removeAll(where: isDynamicReason)
        rest.inputsUsed.removeAll { $0 == "个人心率恢复" }

        if hasPain || painAlertThresholdReached {
            alerts.append("检测到疼痛或异常不适：建议停止本动作并自行确认，系统不会自动结束。")
        }
        if let signal = liveSignal,
           let currentHeartRate = signal.currentHeartRate,
           let maximumHeartRateAlert,
           currentHeartRate >= Double(maximumHeartRateAlert) {
            alerts.append("心率达到个人提醒阈值 \(maximumHeartRateAlert) bpm，请延长休息并确认身体状态。")
        }

        guard let signal = liveSignal, signal.response != nil else {
            appendUnique("实时心率缺失或无效，保留次数、RIR、恢复和历史算法结果", to: &reasons)
            return LiveAdaptationAdvice(
                nextLoadKg: nextLoad,
                adjustment: adjustment,
                rest: rest,
                confidence: .estimated,
                reasons: reasons,
                safetyAlerts: alerts,
                usedLiveHeartRate: false,
                canContinue: true,
                automaticallyEndsExercise: false
            )
        }

        if signal.personalComparison == .slowerThanBaseline {
            rest.recommendedSeconds = min(300, max(rest.lowerSeconds, rest.recommendedSeconds + 60))
            rest.upperSeconds = max(rest.upperSeconds, rest.recommendedSeconds)
            appendUnique("个人心率恢复较基线偏慢，延长 60 秒", to: &rest.reasons)
            appendUnique("个人心率恢复", to: &rest.inputsUsed)
            appendUnique("个人心率恢复偏慢，只用于延长休息并阻止冒进加重", to: &reasons)
            if adjustment == .increase || nextLoad > currentLoadKg {
                nextLoad = currentLoadKg
                adjustment = .hold
            }
        } else if signal.personalComparison == .insufficientHistory {
            appendUnique("个人心率恢复历史不足，显示当前响应但不改变建议", to: &reasons)
        } else {
            appendUnique("个人心率恢复处于自身基线", to: &reasons)
            appendUnique("心率不会单独提高重量", to: &reasons)
        }

        return LiveAdaptationAdvice(
            nextLoadKg: nextLoad,
            adjustment: adjustment,
            rest: rest,
            confidence: calibrationPairs >= 5 ? .measured : .calibrating,
            reasons: reasons,
            safetyAlerts: alerts,
            usedLiveHeartRate: true,
            canContinue: true,
            automaticallyEndsExercise: false
        )
    }

    private static func normalizedBaseReasons(_ value: String) -> [String] {
        var result: [String] = []
        for fragment in value.split(separator: "；").map(String.init) where !isDynamicReason(fragment) {
            appendUnique(fragment, to: &result)
        }
        return result
    }

    private static func isDynamicReason(_ value: String) -> Bool {
        dynamicReasonPrefixes.contains { value.hasPrefix($0) }
            || value == "心率不会单独提高重量"
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        guard !values.contains(value) else { return }
        values.append(value)
    }
}
