// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "A50DockSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "A50HID",
            path: "Sources/A50HID"
        ),
        .executableTarget(
            name: "A50DockSwitch",
            dependencies: ["A50HID"],
            path: "Sources/A50DockSwitch"
        ),
        .executableTarget(
            name: "a50probe",
            dependencies: ["A50HID"],
            path: "Sources/a50probe"
        ),
    ]
)
