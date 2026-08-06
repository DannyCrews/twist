// swift-tools-version: 6.0
import PackageDescription

// Build and test through the Makefile, not `swift` directly — see Makefile for why.
let package = Package(
    name: "Twist",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "TwistKit"),
        .executableTarget(
            name: "Twist",
            dependencies: ["TwistKit"],
            resources: [.copy("Resources/lexicon.twist")]
        ),
        .executableTarget(name: "dicttool", dependencies: ["TwistKit"]),
        .testTarget(name: "TwistKitTests", dependencies: ["TwistKit"]),
    ]
)
