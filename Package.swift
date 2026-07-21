// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FitTuneCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FitTune", targets: ["FitTune"])
    ],
    targets: [
        .target(
            name: "FitTune",
            path: "FitTune",
            exclude: ["App", "Resources", "Services/HealthKitService.swift", "Services/MotionLocationSource.swift", "Views"],
            sources: [
                "Models/DomainModels.swift",
                "Models/WorkoutModels.swift",
                "Models/HealthMetricModels.swift",
                "Engine/TrainingEngine.swift",
                "Engine/RecoveryEngine.swift",
                "Engine/LiveAdaptationEngine.swift",
                "Engine/SummaryEngine.swift",
                "Engine/TrendEngine.swift",
                "Engine/EnergyEngine.swift",
                "Services/HealthImportModels.swift",
                "Services/LiveSensorSource.swift",
                "Services/LiveSensorCoordinator.swift",
                "Services/BluetoothHeartRateSource.swift",
                "Services/DataExportService.swift",
                "Store/AppStore.swift"
            ]
        ),
        .testTarget(
            name: "FitTuneTests",
            dependencies: ["FitTune"],
            path: "FitTuneTests"
        )
    ]
)
