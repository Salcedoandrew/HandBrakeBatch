// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HandBrakeBatch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "HandBrakeBatch", path: "Sources/HandBrakeBatch")
    ]
)
