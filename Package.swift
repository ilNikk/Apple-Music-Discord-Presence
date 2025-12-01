// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MusicDiscordPresence",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "MusicDiscordPresence",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/Info.plist"])
            ]
        ),
    ]
)
