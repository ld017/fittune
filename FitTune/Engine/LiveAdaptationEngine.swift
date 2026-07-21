import Foundation

struct LiveHeartRateSignal: Equatable {
    var peakHeartRate: Double?
    var currentHeartRate: Double?
    var secondsAfterSet: Int
    var validity: LiveMetricValidity
    var sourceName: String
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
    static func adapt(
        baseRecommendation: SetRecommendation,
        baseRest: RestRecommendation,
        currentLoadKg: Double,
        liveSignal: LiveHeartRateSignal?,
        calibrationSessions: Int,
        hasPain: Bool,
        painAlertThresholdReached: Bool,
        maximumHeartRateAlert: Int?
    ) -> LiveAdaptationAdvice {
        var nextLoad = baseRecommendation.nextLoadKg
        var adjustment = baseRecommendation.adjustment
        var rest = baseRest
        var reasons = [baseRecommendation.reason]
        var alerts: [String] = []
        var usedHeartRate = false

        if hasPain || painAlertThresholdReached {
            alerts.append("检测到疼痛或异常不适：建议停止本动作并自行确认，系统不会自动结束。")
        }
        if let signal = liveSignal,
           let currentHeartRate = signal.currentHeartRate,
           let maximumHeartRateAlert,
           currentHeartRate >= Double(maximumHeartRateAlert) {
            alerts.append("心率达到个人提醒阈值 \(maximumHeartRateAlert) bpm，请延长休息并确认身体状态。")
        }

        guard let signal = liveSignal,
              signal.validity == .valid,
              let peak = signal.peakHeartRate,
              let current = signal.currentHeartRate else {
            reasons.append("实时心率缺失或无效，保留次数、RIR、恢复和历史算法结果")
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

        usedHeartRate = true
        let recovery = max(0, peak - current)
        let poorRecovery = (signal.secondsAfterSet >= 120 && recovery < 22)
            || (signal.secondsAfterSet >= 60 && signal.secondsAfterSet < 120 && recovery < 12)
        if poorRecovery {
            rest.recommendedSeconds = min(600, max(rest.recommendedSeconds + 60, rest.lowerSeconds))
            rest.upperSeconds = max(rest.upperSeconds, rest.recommendedSeconds)
            rest.reasons.append("\(signal.secondsAfterSet) 秒心率恢复偏慢，延长 60 秒")
            rest.inputsUsed.append("实时心率恢复")
            reasons.append("心率恢复偏慢，只用于延长休息并阻止冒进加重")
            if adjustment == .increase || nextLoad > currentLoadKg {
                nextLoad = currentLoadKg
                adjustment = .hold
            }
        } else {
            reasons.append("心率恢复未触发保守修正；心率不会单独提高重量")
            if baseRecommendation.adjustment != .increase {
                nextLoad = min(nextLoad, currentLoadKg)
            }
        }
        return LiveAdaptationAdvice(
            nextLoadKg: nextLoad,
            adjustment: adjustment,
            rest: rest,
            confidence: calibrationSessions < 3 ? .calibrating : .measured,
            reasons: reasons,
            safetyAlerts: alerts,
            usedLiveHeartRate: usedHeartRate,
            canContinue: true,
            automaticallyEndsExercise: false
        )
    }
}
