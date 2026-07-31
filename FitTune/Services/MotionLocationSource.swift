import Foundation
import CoreLocation
import CoreMotion
import Observation

@MainActor
@Observable
final class MotionLocationSource: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var distanceMeters = 0.0
    private(set) var steps = 0
    private(set) var cadence: Double?
    private(set) var statusMessage = "尚未开始采集"
    var onSample: ((WorkoutMetricSample) -> Void)?
    var onDataGap: ((String) -> Void)?

    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var lastLocation: CLLocation?
    private var modality: CardioModality?
    private var sport: SportKind?
    private var elevation = ElevationAccumulator()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }

    func start(modality: CardioModality, from date: Date = .now) {
        resetSession()
        self.modality = modality
        sport = nil
        if [.running, .briskWalking, .inclineWalking, .cycling].contains(modality) {
            locationManager.requestWhenInUseAuthorization()
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.startUpdatingLocation()
        }
        if CMPedometer.isStepCountingAvailable(), modality != .swimming {
            pedometer.startUpdates(from: date) { [weak self] data, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.onDataGap?("运动传感器中断：\(error.localizedDescription)")
                        return
                    }
                    guard let data else { return }
                    self.steps = data.numberOfSteps.intValue
                    self.cadence = data.currentCadence.map { $0.doubleValue * 60 }
                    let distance = data.distance?.doubleValue
                    if let distance { self.distanceMeters = max(self.distanceMeters, distance) }
                    let provenance = MetricProvenance(source: .phoneSensor, sourceName: "iPhone 运动传感器", confidence: .measured, coverage: 1, sampledAt: .now)
                    self.onSample?(WorkoutMetricSample(timestamp: .now, cadence: self.cadence, steps: self.steps, distanceMeters: distance, provenance: provenance))
                }
            }
        }
        statusMessage = modality == .swimming ? "无 Watch 时不估算游泳划水" : "iPhone 传感器采集中"
    }

    func start(sport: SportKind, environment: SportEnvironment, from date: Date = .now) {
        resetSession()
        modality = nil
        self.sport = sport
        let usesOutdoorLocation = environment == .outdoor && [.soccer, .climbing, .hiking, .mountaineering, .trailRunning].contains(sport)
        if usesOutdoorLocation {
            locationManager.requestWhenInUseAuthorization()
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.startUpdatingLocation()
        }
        if CMPedometer.isStepCountingAvailable(), sport != .climbing {
            startPedometer(from: date)
        }
        statusMessage = usesOutdoorLocation ? "iPhone 定位与运动传感器采集中" : "iPhone 运动传感器采集中"
    }

    func resume(modality: CardioModality, from date: Date = .now) {
        self.modality = modality
        sport = nil
        if [.running, .briskWalking, .inclineWalking, .cycling].contains(modality) {
            locationManager.startUpdatingLocation()
        }
        if CMPedometer.isStepCountingAvailable(), modality != .swimming { startPedometer(from: date) }
        statusMessage = modality == .swimming ? "无 Watch 时不估算游泳划水" : "iPhone 传感器采集中"
    }

    func resume(sport: SportKind, environment: SportEnvironment, from date: Date = .now) {
        modality = nil
        self.sport = sport
        let usesOutdoorLocation = environment == .outdoor && [.soccer, .climbing, .hiking, .mountaineering, .trailRunning].contains(sport)
        if usesOutdoorLocation { locationManager.startUpdatingLocation() }
        if CMPedometer.isStepCountingAvailable(), sport != .climbing { startPedometer(from: date) }
        statusMessage = usesOutdoorLocation ? "iPhone 定位与运动传感器采集中" : "iPhone 运动传感器采集中"
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        pedometer.stopUpdates()
        lastLocation = nil
        statusMessage = "采集已停止"
    }

    private func resetSession() {
        stop()
        distanceMeters = 0
        steps = 0
        cadence = nil
        lastLocation = nil
        elevation.reset()
    }

    private func startPedometer(from date: Date) {
        pedometer.startUpdates(from: date) { [weak self] data, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.onDataGap?("运动传感器中断：\(error.localizedDescription)")
                    return
                }
                guard let data else { return }
                self.steps = data.numberOfSteps.intValue
                self.cadence = data.currentCadence.map { $0.doubleValue * 60 }
                let distance = data.distance?.doubleValue
                if let distance { self.distanceMeters = max(self.distanceMeters, distance) }
                let provenance = MetricProvenance(source: .phoneSensor, sourceName: "iPhone 运动传感器", confidence: .measured, coverage: 1, sampledAt: .now)
                self.onSample?(WorkoutMetricSample(timestamp: .now, cadence: self.cadence, steps: self.steps, distanceMeters: distance, provenance: provenance))
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50 {
            if let lastLocation {
                let segment = location.distance(from: lastLocation)
                if segment >= 0 && segment < 500 { distanceMeters += segment }
            }
            lastLocation = location
            _ = elevation.ingest(altitudeMeters: location.altitude, verticalAccuracy: location.verticalAccuracy)
            let provenance = MetricProvenance(source: .phoneSensor, sourceName: "iPhone 定位", confidence: .measured, coverage: 1, sampledAt: location.timestamp)
            onSample?(WorkoutMetricSample(
                timestamp: location.timestamp,
                distanceMeters: distanceMeters,
                altitudeMeters: elevation.altitudeMeters,
                elevationGainMeters: elevation.elevationGainMeters,
                speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
                provenance: provenance
            ))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            statusMessage = "定位不可用，继续记录时长和其他可用数据"
            onDataGap?("定位权限不可用")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        statusMessage = "定位暂时中断，训练仍在保存"
        onDataGap?("定位中断：\(error.localizedDescription)")
    }
}
