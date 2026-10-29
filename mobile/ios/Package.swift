// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConsegVida",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ConsegVida", targets: ["ConsegVida"])],
    dependencies: [.package(name: "ConsegVidaCore", path: "../core-swift")],
    targets: [
        .target(
            name: "ConsegVida",
            dependencies: [.product(name: "ConsegVidaCore", package: "ConsegVidaCore")],
            resources: [.copy("Resources/content.json")]
        )
    ]
)
