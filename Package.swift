// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "k5k1prog-mac",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "K5K1Prog", targets: ["K5K1Prog"]),
        .executable(name: "k5emu", targets: ["k5emu"]),
    ],
    dependencies: [
        // in-app updates (Check for Updates…); pinned minor, tools in scripts/release.sh use the same version
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMinor(from: "2.10.0")),
    ],
    targets: [
        .target(name: "K5Core"),
        .target(name: "K5Sim", dependencies: ["K5Core"]),
        .executableTarget(name: "K5K1Prog", dependencies: ["K5Core", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "k5emu", dependencies: ["K5Sim"]),
        .testTarget(name: "K5CoreTests", dependencies: ["K5Core", "K5Sim"]),
    ]
)
