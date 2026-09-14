// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimplexFlame",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SimplexFlame", targets: ["SimplexFlame"])],
    targets: [.executableTarget(name: "SimplexFlame", resources: [.copy("Flame.metal")])]
)
