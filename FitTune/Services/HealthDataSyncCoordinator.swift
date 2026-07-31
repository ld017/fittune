import Foundation
import Observation
import SwiftUI

enum HealthRefreshReason: String, Equatable {
    case initial
    case observer
    case foreground
    case manual
}

@MainActor
@Observable
final class HealthDataSyncCoordinator {
    private(set) var snapshot: DailyHealthSnapshot
    private(set) var permissions: [DailyHealthMetric: Bool]
    private(set) var lastErrorMessage: String?
    private(set) var isRefreshing = false
    private(set) var lastRefreshReason: HealthRefreshReason?

    private let service: HealthKitService
    private var started = false
    private var refreshGate = HealthRefreshGate()

    init(service: HealthKitService) {
        self.service = service
        let permissions = Dictionary(uniqueKeysWithValues: DailyHealthMetric.allCases.map { ($0, false) })
        self.permissions = permissions
        self.snapshot = DailyHealthSnapshotReducer.reduce(
            samples: [],
            day: .now,
            timeZone: .current,
            permissions: permissions
        )
    }

    func requestAuthorizationAndStart() async {
        guard !started else {
            await refreshToday(reason: .foreground)
            return
        }
        permissions = await service.requestDailyReadAuthorization()
        started = true
        service.startDailyObservation { [weak self] in
            Task { @MainActor in await self?.refreshToday(reason: .observer) }
        }
        await refreshToday(reason: .initial)
    }

    func refreshToday(reason: HealthRefreshReason) async {
        guard refreshGate.requestRefresh() else { return }
        var resolvedReason = reason
        repeat {
            isRefreshing = true
            lastRefreshReason = resolvedReason
            let samples: [DailyHealthSample] = await withCheckedContinuation { continuation in
                service.fetchDailyHealthSamples(day: .now, timeZone: .current) { samples in
                    continuation.resume(returning: samples)
                }
            }
            let refreshed = DailyHealthSnapshotReducer.reduce(
                samples: samples,
                day: .now,
                timeZone: .current,
                permissions: permissions,
                now: .now
            )
            if refreshed != snapshot { snapshot = refreshed }
            lastErrorMessage = service.isAvailable ? nil : "此设备无法读取 Apple 健康数据"
            resolvedReason = .observer
        } while refreshGate.finishRefreshAndBeginPending()
        isRefreshing = false
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        if phase == .active {
            if started { await refreshToday(reason: .foreground) }
            else { await requestAuthorizationAndStart() }
        }
    }

    func stop() {
        service.stopDailyObservation()
        started = false
    }
}
