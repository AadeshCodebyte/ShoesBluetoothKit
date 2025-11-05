// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShoesBluetoothKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "ShoesBluetoothKit",
            targets: ["ShoesBluetoothKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ShoesBluetoothKit",
            dependencies: []
        ),
        .testTarget(
            name: "ShoesBluetoothKitTests",
            dependencies: ["ShoesBluetoothKit"]
        )
    ]
)
