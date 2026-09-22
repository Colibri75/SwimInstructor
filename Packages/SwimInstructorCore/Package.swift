// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwimInstructorCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "SwimInstructorCore", targets: ["SwimInstructorCore"])
    ],
    targets: [
        .target(name: "SwimInstructorCore"),
        .testTarget(name: "SwimInstructorCoreTests", dependencies: ["SwimInstructorCore"])
    ]
)
