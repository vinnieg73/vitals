// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Vitals",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Vitals", path: "Sources/Vitals"),
    ]
)
