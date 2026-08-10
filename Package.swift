// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutumnJobs",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AutumnJobs", targets: ["AutumnJobsApp"])
    ],
    targets: [
        .executableTarget(
            name: "AutumnJobsApp",
            path: "Sources/AutumnJobsApp"
        ),
        .testTarget(
            name: "AutumnJobsAppTests",
            dependencies: ["AutumnJobsApp"],
            path: "Tests/AutumnJobsAppTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
