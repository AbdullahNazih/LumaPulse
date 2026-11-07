// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LumaPulse", platforms: [.macOS(.v13)], products: [.executable(name: "LumaPulse", targets: ["LumaPulse"])], targets: [.executableTarget(name: "LumaPulse")])
