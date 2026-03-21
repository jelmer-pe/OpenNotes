// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalNotes",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "LocalNotes",
            dependencies: ["HotKey"],
            path: "LocalNotes",
            resources: [
                .copy("Resources/editor.html"),
                .copy("Resources/editor.bundle.js"),
                .copy("Resources/editor.css"),
            ]
        ),
    ]
)
