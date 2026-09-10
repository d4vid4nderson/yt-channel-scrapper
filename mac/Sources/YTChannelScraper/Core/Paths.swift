import Foundation

/// Where the app's binaries and files live.
enum Paths {
    static let appName = "YT Channel Scraper"

    /// The vendored ffmpeg / ffprobe / deno / yt-dlp, wherever this copy is running from.
    ///
    /// Inside the bundle they sit in Resources/vendor. Under `swift run` there is no
    /// bundle, so the repo's own vendor/ is used instead — which is what makes the app
    /// runnable from a terminal during development.
    static let vendor: URL = {
        if let override = ProcessInfo.processInfo.environment["YTCS_VENDOR"] {
            return URL(fileURLWithPath: override)
        }
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("vendor")
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("yt-dlp_macos").path) {
                return bundled
            }
        }
        // Sources/YTChannelScraper/Core/Paths.swift -> repo root
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Core
            .deletingLastPathComponent()   // YTChannelScraper
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // mac
            .appendingPathComponent("vendor")
    }()

    /// Where the in-app updater puts a newer yt-dlp. The bundled copy cannot be
    /// replaced — the bundle is signed and read-only — so a newer one lands here.
    static var ytdlpOverride: URL { support.appendingPathComponent("bin/yt-dlp_macos") }

    /// The yt-dlp to actually run: a downloaded update if there is one, else the copy
    /// shipped in the bundle. Resolved per call, so an update applies to the very next
    /// scrape or download without a relaunch.
    static var ytdlp: URL {
        FileManager.default.isExecutableFile(atPath: ytdlpOverride.path)
            ? ytdlpOverride
            : vendor.appendingPathComponent("yt-dlp_macos")
    }
    static var hasFFmpeg: Bool {
        FileManager.default.fileExists(atPath: vendor.appendingPathComponent("ffmpeg").path)
    }
    /// YouTube gates anything above 360p behind a solved JS challenge, which yt-dlp
    /// farms out to a JS runtime. Without Deno present there is no point asking.
    static var hasJSRuntime: Bool {
        FileManager.default.fileExists(atPath: vendor.appendingPathComponent("deno").path)
    }

    static let support: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(appName)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let downloads: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/\(appName)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
