// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ruche",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Ruche", path: "Sources/Ruche")
    ]
)
