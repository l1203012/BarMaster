// swift-tools-version:5.8
// Keep the target graph in sync with Scripts/targets.sh, which builds the
// same modules with plain swiftc when only the Command Line Tools are installed.
import PackageDescription

let package = Package(
    name: "BarMaster",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BarMasterApp", targets: ["BarMasterApp"]),
    ],
    targets: [
        .executableTarget(name: "BarMasterApp"),
    ]
)
