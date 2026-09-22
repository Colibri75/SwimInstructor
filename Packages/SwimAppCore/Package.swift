// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwimAppCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "SwimAppCore", targets: ["SwimAppCore"])
    ],
    targets: [
        .target(name: "SwimAppCore"),
        .testTarget(name: "SwimAppCoreTests", dependencies: ["SwimAppCore"])
    ]
)
