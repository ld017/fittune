import Foundation

@MainActor
extension AppStore {
    func startSportSession(
        kind: SportKind,
        environment: SportEnvironment,
        intensity: SportIntensity,
        at startedAt: Date = .now
    ) {
        guard activeWorkoutDraft == nil, activeCardioDraft == nil, activeSportDraft == nil else { return }
        let resolvedEnvironment = kind.availableEnvironments.contains(environment) ? environment : kind.defaultEnvironment
        activeSportDraft = SportSessionDraft(
            kind: kind,
            environment: resolvedEnvironment,
            intensity: intensity,
            startedAt: startedAt,
            lastCheckpointAt: startedAt
        )
        sportMetricDraftID = activeSportDraft?.id
        sportMetricSampleIDs = []
        if persist() { lastSportMetricPersistAt = startedAt }
    }

    func appendSportMetricSample(
        _ sample: WorkoutMetricSample,
        validity: LiveMetricValidity = .valid,
        now: Date = .now
    ) {
        guard var draft = activeSportDraft else { return }
        prepareSportMetricTracking(for: draft)
        guard validity == .valid else {
            let reason = "传感器样本异常（\(validity.rawValue)），该点未参与计算"
            if !draft.dataGapReasons.contains(reason) { draft.dataGapReasons.append(reason) }
            draft.updatedAt = now
            activeSportDraft = draft
            return
        }
        guard sportMetricSampleIDs.insert(sample.id).inserted else { return }
        draft.metricSamples.append(sample)
        if !draft.sourceNames.contains(sample.provenance.sourceName) {
            draft.sourceNames.append(sample.provenance.sourceName)
        }
        draft.updatedAt = now
        activeSportDraft = draft
        if Self.shouldPersistLiveMetric(lastPersistedAt: lastSportMetricPersistAt, now: now), persist() {
            lastSportMetricPersistAt = now
            activeSportDraft?.lastCheckpointAt = now
        }
    }

    func markSportDataGap(_ reason: String, at date: Date = .now) {
        guard var draft = activeSportDraft else { return }
        if !draft.dataGapReasons.contains(reason) { draft.dataGapReasons.append(reason) }
        draft.updatedAt = date
        activeSportDraft = draft
        if persist() { lastSportMetricPersistAt = date }
    }

    func pauseSportSession(at date: Date = .now) {
        guard var draft = activeSportDraft, draft.pausedAt == nil, date >= draft.startedAt else { return }
        draft.pausedAt = date
        draft.updatedAt = date
        draft.lastCheckpointAt = date
        activeSportDraft = draft
        if persist() { lastSportMetricPersistAt = date }
    }

    func resumeSportSession(at date: Date = .now) {
        guard var draft = activeSportDraft, let pausedAt = draft.pausedAt, date >= pausedAt else { return }
        draft.pauseIntervals.append(SportPauseInterval(startedAt: pausedAt, endedAt: date))
        draft.pausedAt = nil
        draft.updatedAt = date
        draft.lastCheckpointAt = date
        activeSportDraft = draft
        if persist() { lastSportMetricPersistAt = date }
    }

    func checkpointActiveSport(at date: Date = .now) {
        guard activeSportDraft != nil else { return }
        activeSportDraft?.updatedAt = date
        activeSportDraft?.lastCheckpointAt = date
        if persist() { lastSportMetricPersistAt = date }
    }

    func discardSportSession() {
        activeSportDraft = nil
        persist()
        resetSportMetricTracking()
    }

    @discardableResult
    func finishSportSession(
        status: WorkoutCompletionStatus,
        sessionRPE: Double,
        at completedAt: Date = .now
    ) -> SportSessionRecord? {
        guard var draft = activeSportDraft, completedAt >= draft.startedAt else { return nil }
        if let pausedAt = draft.pausedAt, completedAt >= pausedAt {
            draft.pauseIntervals.append(.init(startedAt: pausedAt, endedAt: completedAt))
            draft.pausedAt = nil
        }
        let analysis = SportAnalysisEngine.analyze(
            draft: draft,
            completedAt: completedAt,
            sessionRPE: min(10, max(0, sessionRPE)),
            weightKg: latestWeight ?? profile?.bodyWeightKg ?? 70,
            restingHeartRate: profile?.restingHeartRate,
            maximumHeartRate: profile?.measuredMaxHeartRate ?? profile?.ageYears.map { 208 - 0.7 * Double($0) }
        )
        let minutes = Int((analysis.effectiveDurationSeconds / 60).rounded())
        let summary = "有效 \(minutes) 分钟 · 主动热量约 \(Int(analysis.activeEnergyKcal.value.rounded())) kcal（\(Int(analysis.activeEnergyKcal.lowerBound.rounded()))–\(Int(analysis.activeEnergyKcal.upperBound.rounded()))）· 负荷 \(Int(analysis.sessionRPELoadAU.rounded())) AU"
        let record = SportSessionRecord(
            id: draft.id,
            kind: draft.kind,
            environment: draft.environment,
            intensity: draft.intensity,
            startedAt: draft.startedAt,
            completedAt: completedAt,
            completionStatus: status,
            sessionRPE: min(10, max(0, sessionRPE)),
            analysis: analysis,
            metricSamples: draft.metricSamples,
            summary: summary
        )
        sportWorkouts.insert(record, at: 0)
        activeSportDraft = nil
        persist()
        resetSportMetricTracking()
        presentedSportRecord = record
        return record
    }

    func deleteSportWorkout(id: UUID) {
        guard let index = sportWorkouts.firstIndex(where: { $0.id == id }) else { return }
        deletedSportWorkouts.insert(sportWorkouts.remove(at: index), at: 0)
        persist()
    }

    func restoreSportWorkout(id: UUID) {
        guard let index = deletedSportWorkouts.firstIndex(where: { $0.id == id }) else { return }
        sportWorkouts.append(deletedSportWorkouts.remove(at: index))
        sportWorkouts.sort { $0.completedAt > $1.completedAt }
        persist()
    }

    func permanentlyDeleteSportWorkout(id: UUID) {
        guard deletedSportWorkouts.contains(where: { $0.id == id }) else { return }
        deletedSportWorkouts.removeAll { $0.id == id }
        persist()
    }

    func clearSportMetrics(id: UUID) {
        guard let index = sportWorkouts.firstIndex(where: { $0.id == id }) else { return }
        sportWorkouts[index].metricSamples = []
        persist()
    }

    private func prepareSportMetricTracking(for draft: SportSessionDraft) {
        guard sportMetricDraftID != draft.id else { return }
        sportMetricDraftID = draft.id
        sportMetricSampleIDs = Set(draft.metricSamples.map(\.id))
        lastSportMetricPersistAt = draft.lastCheckpointAt ?? draft.updatedAt
    }
}
