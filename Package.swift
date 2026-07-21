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
            exclude: ["App", "Resources", "Services", "Views"],
            sources: ["Models/DomainModels.swift", "Engine/TrainingEngine.swift", "Store/AppStore.swift"]
        ),
        .testTarget(
            name: "FitTuneTests",
            dependencies: ["FitTune"],
            path: "FitTuneTests"
        )
    ]
)
