// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AIMonitor", platforms: [.macOS(.v14)], products: [
    .executable(name: "AIMonitor", targets: ["AIMonitor"])
], targets: [
    .target(name: "MonitorCore"),
    .executableTarget(name: "AIMonitor", dependencies: ["MonitorCore"]),
    .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
    .testTarget(name: "AIMonitorTests", dependencies: ["AIMonitor", "MonitorCore"])
])
