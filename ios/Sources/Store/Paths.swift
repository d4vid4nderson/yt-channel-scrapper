import Foundation

/// Where the app's files live on iOS.
///
/// The Mac version of this type resolves vendored binaries — yt-dlp, ffmpeg, Deno — and
/// none of that exists here. What is left is the two directories, and one decision worth
/// stating: downloads go in **Documents**, not in Application Support.
///
/// Documents is the only directory the Files app can see, and the Info.plist pairs it
/// with `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`. That is what
/// makes a downloaded video reachable without this app — you can AirDrop it, open it in
/// another player, or copy it off over a cable. A downloader whose files can only be
/// opened by the downloader is not much of a downloader.
enum Paths {
    /// Matches the Mac app's name so an exported library reads as coming from the same
    /// product. `LibraryArchive` stamps it into the file.
    static let appName = "YT Channel Scraper"

    /// Visible in Files under "On My iPhone → YT Scraper".
    static let downloads: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return ensure(documents)
    }()

    /// The library JSON and anything else the user never needs to see. Excluded from
    /// backup would be wrong — the saved channels are small and worth restoring.
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return ensure(base.appendingPathComponent(appName, isDirectory: true))
    }()

    /// Half-finished stream files. Under Caches so that a download killed mid-flight
    /// cannot leave the user paying for storage forever — iOS reclaims this directory
    /// under pressure, and a partial stream is worth nothing anyway.
    static let scratch: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ensure(caches.appendingPathComponent("streams", isDirectory: true))
    }()

    private static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A filename that keeps the title readable but cannot escape the directory or
    /// upset the filesystem.
    ///
    /// Mirrors what the Mac asks yt-dlp for with `--restrict-filenames` and
    /// `%(title).150B [%(id)s].%(ext)s`: the id is kept so two videos with the same
    /// title do not collide, and the title is cut well short of any path limit.
    static func filename(title: String, id: String, extension ext: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        var cleaned = title.components(separatedBy: forbidden).joined(separator: " ")
        cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if cleaned.count > 120 { cleaned = String(cleaned.prefix(120)) }
        if cleaned.isEmpty { cleaned = id }
        return "\(cleaned) [\(id)].\(ext)"
    }

    /// The same name, with a number appended if it is taken. Two downloads of the same
    /// video should not silently overwrite one another.
    static func available(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for suffix in 2...99 {
            let candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(base) (\(suffix)).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}
