import Foundation

enum HealthSourceKind: String, Codable, Equatable, Hashable {
    case appleWatch
    case huaweiHealth
    case other
}

enum SleepStage: String, Codable, Equatable {
    case awake
    case asleep
    case core
    case deep
    case rem
    case unknown

    var countsAsSleep: Bool {
        switch self {
        case .asleep, .core, .deep, .rem: true
        case .awake, .unknown: false
        }
    }
}

struct SleepImportSample: Codable, Equatable {
    var externalID: String
    var start: Date
    var end: Date
    var stage: SleepStage
    var source: HealthSourceKind
}

struct SleepImportSummary: Codable, Equatable {
    var totalSleepMinutes: Double
    var awakeMinutes: Double
    var interruptionCount: Int
    var sourceKinds: [HealthSourceKind]
    var importedExternalIDs: [String]
}

enum HealthSourceClassifier {
    static func classify(sourceName: String, bundleIdentifier: String?, productType: String?) -> HealthSourceKind {
        let evidence = [sourceName, bundleIdentifier ?? "", productType ?? ""].joined(separator: " ").lowercased()
        if evidence.contains("huawei") || evidence.contains("华为") { return .huaweiHealth }
        if evidence.contains("watch") && (evidence.contains("apple") || evidence.contains("com.apple") || productType?.lowercased().contains("watch") == true) {
            return .appleWatch
        }
        return .other
    }
}

enum HealthImportCapabilities {
    static let supportsGenericStressScore = false
    static let stressFallback: RecoveryValueProvenance = .manual
}

enum HealthImportMerger {
    static func mergeSleep(_ input: [SleepImportSample]) -> SleepImportSummary {
        var seen = Set<String>()
        let samples = input.filter { sample in
            guard sample.end > sample.start, !seen.contains(sample.externalID) else { return false }
            seen.insert(sample.externalID)
            return true
        }
        let boundaries = Array(Set(samples.flatMap { [$0.start, $0.end] })).sorted()
        var asleepSeconds = 0.0
        var awakeSeconds = 0.0
        var awakeSegments = 0
        for index in 0..<max(0, boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            let covering = samples.filter { $0.start < end && $0.end > start }
            guard !covering.isEmpty else { continue }
            let duration = end.timeIntervalSince(start)
            if covering.contains(where: { $0.stage == .awake }) {
                awakeSeconds += duration
                awakeSegments += 1
            } else if covering.contains(where: { $0.stage.countsAsSleep }) {
                asleepSeconds += duration
            }
        }
        let sources = Array(Set(samples.map(\.source))).sorted { $0.rawValue < $1.rawValue }
        return SleepImportSummary(
            totalSleepMinutes: asleepSeconds / 60,
            awakeMinutes: awakeSeconds / 60,
            interruptionCount: awakeSegments,
            sourceKinds: sources,
            importedExternalIDs: samples.map(\.externalID).sorted()
        )
    }

    static func mergeRestingHeartRates(
        existing: [RestingHeartRateSample],
        incoming: [RestingHeartRateSample]
    ) -> [RestingHeartRateSample] {
        var result = existing
        var externalKeys = Set(existing.compactMap { sample in
            sample.externalID.map { "\(sample.source.rawValue):\($0)" }
        })
        for sample in incoming where sample.bpm > 0 {
            if let externalID = sample.externalID {
                let key = "\(sample.source.rawValue):\(externalID)"
                guard !externalKeys.contains(key) else { continue }
                externalKeys.insert(key)
            } else if result.contains(where: {
                $0.source == sample.source
                    && abs($0.date.timeIntervalSince(sample.date)) < 1
                    && abs($0.bpm - sample.bpm) < 0.01
            }) {
                continue
            }
            result.append(sample)
        }
        return result.sorted { $0.date < $1.date }
    }
}
