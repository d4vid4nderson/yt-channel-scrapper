// swift-tools-version: 6.0
import PackageDescription

// The app ships as a hand-assembled .app bundle (see build-mac-app.sh) rather than an
// Xcode project: the bundle needs three vendored binaries dropped into Resources, which
// is a shell script's job, and keeping the sources in SwiftPM means `swift build` alone
// is enough to typecheck the whole thing from a terminal.
let package = Package(
    name: "YTChannelScraper",
    platforms: [.macOS(.v15)],  // pointerStyle, for real cursor feedback
    targets: [
        .executableTarget(
            name: "YTChannelScraper",
            path: "Sources/YTChannelScraper",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
