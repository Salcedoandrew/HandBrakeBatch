// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HandBrakeBatch",
    platforms: [.macOS(.v13)],
    targets: [
        // The app's code lives in a library target so tests can import it.
        // (An executable target can't be imported by a test target.)
        .target(name: "HandBrakeBatchCore", path: "Sources/HandBrakeBatchCore"),
        // Thin entry point: just the SwiftUI App and the CLI/GUI dispatch.
        .executableTarget(
            name: "HandBrakeBatch",
            dependencies: ["HandBrakeBatchCore"],
            path: "Sources/HandBrakeBatch"
        ),
        .testTarget(
            name: "HandBrakeBatchTests",
            dependencies: ["HandBrakeBatchCore"]
        ),
    ]
)
