// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConsegVidaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ConsegVidaCore", targets: ["ConsegVidaCore"])],
    targets: [
        .target(name: "ConsegVidaCore"),
        .testTarget(
            name: "ConsegVidaCoreTests",
            dependencies: ["ConsegVidaCore"],
            resources: [.copy("Fixtures/content.json")]
        )
    ]
)
