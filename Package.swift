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
            exclude: ["App", "Resources", "Models/WorkoutActivityAttributes.swift", "Services/HealthKitService.swift", "Services/MotionLocationSource.swift", "Services/WatchWorkoutBridge.swift", "Services/WorkoutActivityController.swift", "Views"],
            sources: [
                "Models/DomainModels.swift",
                "Models/ExerciseCatalogModels.swift",
                "Models/WorkoutModels.swift",
                "Models/HealthMetricModels.swift",
                "Engine/TrainingEngine.swift",
                "Engine/ExerciseCatalog.swift",
                "Engine/ExerciseReplacementEngine.swift",
                "Engine/RecoveryEngine.swift",
                "Engine/LiveAdaptationEngine.swift",
                "Engine/SummaryEngine.swift",
                "Engine/TrendEngine.swift",
                "Engine/EnergyEngine.swift",
                "Engine/WorkoutActivitySnapshot.swift",
                "Services/HealthImportModels.swift",
                "Services/LiveSensorSource.swift",
                "Services/LiveSensorCoordinator.swift",
                "Services/BluetoothHeartRateSource.swift",
                "Services/DataExportService.swift",
                "Services/WatchMetricMerge.swift",
                "Store/AppStore.swift"
            ]
        ),
        .testTarget(
            name: "FitTuneTests",
            dependencies: ["FitTune"],
            path: "FitTuneTests",
            resources: [
                .copy("Fixtures/EnergyBenchmarks.json"),
                .copy("Fixtures/RestRecommendationBenchmarks.json"),
                .copy("Fixtures/E1RMBenchmarks.json"),
                .copy("Fixtures/RecoveryBenchmarks.json"),
                .copy("Fixtures/HealthDeduplicationBenchmarks.json")
            ]
        )
    ]
)
