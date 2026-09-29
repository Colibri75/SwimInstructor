// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwimInstructorCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        // `swift test` (used by both CI and local package testing) builds for macOS, the host
        // platform - without an explicit minimum here, SwiftPM falls back to a very old default
        // that predates HealthKit and Combine, so every HK/@Published symbol fails to compile.
        .macOS(.v13)
    ],
    products: [
        .library(name: "SwimInstructorCore", targets: ["SwimInstructorCore"])
    ],
    targets: [
        .target(name: "SwimInstructorCore"),
        .testTarget(name: "SwimInstructorCoreTests", dependencies: ["SwimInstructorCore"])
    ]
)
