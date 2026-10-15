// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "k5k1prog-mac",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "K5K1Prog", targets: ["K5K1Prog"]),
        .executable(name: "k5emu", targets: ["k5emu"]),
    ],
    targets: [
        .target(name: "K5Core"),
        .target(name: "K5Sim", dependencies: ["K5Core"]),
        .executableTarget(name: "K5K1Prog", dependencies: ["K5Core"]),
        .executableTarget(name: "k5emu", dependencies: ["K5Sim"]),
        .testTarget(name: "K5CoreTests", dependencies: ["K5Core", "K5Sim"]),
    ]
)
