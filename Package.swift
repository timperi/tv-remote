// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ATVRemoteCore",
    products: [
        .library(name: "ATVRemoteCore", targets: ["ATVRemoteCore"])
    ],
    targets: [
        .target(name: "ATVRemoteCore"),
        .testTarget(name: "ATVRemoteCoreTests", dependencies: ["ATVRemoteCore"])
    ]
)
