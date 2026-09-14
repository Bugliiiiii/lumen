// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonitorSwitchMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MonitorSwitchMac", targets: ["MonitorSwitchMac"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/waydabber/AppleSiliconDDC.git",
            revision: "67ff964ab8123d9d35fadf7d8e1a7c677d31da14"
        ),
    ],
    targets: [
        .executableTarget(
            name: "MonitorSwitchMac",
            dependencies: [.product(name: "AppleSiliconDDC", package: "AppleSiliconDDC")]
        ),
    ]
)
