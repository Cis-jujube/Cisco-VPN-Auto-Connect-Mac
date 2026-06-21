// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CiscoVPNAutoConnect",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CiscoVPNCore",
            targets: ["CiscoVPNCore"]
        ),
        .executable(
            name: "CiscoVPNMac",
            targets: ["CiscoVPNMac"]
        ),
        .executable(
            name: "CiscoVPNCoreSelfTests",
            targets: ["CiscoVPNCoreSelfTests"]
        )
    ],
    targets: [
        .target(
            name: "CiscoVPNCore"
        ),
        .executableTarget(
            name: "CiscoVPNMac",
            dependencies: ["CiscoVPNCore"]
        ),
        .executableTarget(
            name: "CiscoVPNCoreSelfTests",
            dependencies: ["CiscoVPNCore"]
        )
    ]
)
