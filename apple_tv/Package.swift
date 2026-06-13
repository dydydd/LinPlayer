// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinPlayerTV",
    platforms: [
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "LinPlayerTV",
            targets: ["LinPlayerTV"]
        ),
    ],
    targets: [
        .target(
            name: "LinPlayerTV",
            path: "LinPlayerTV"
        ),
    ]
)
