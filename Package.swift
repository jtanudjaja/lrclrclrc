// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "lrclrclrc",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "lrclrclrc",
            path: "Sources/lrclrclrc"
        )
    ]
)
