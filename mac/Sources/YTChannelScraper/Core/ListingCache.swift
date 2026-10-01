import CryptoKit
import Foundation

/// Each channel tab as it was last read, kept on disk, so opening it again asks nothing.
///
/// A channel is read by walking it with yt-dlp, which takes seconds even for the first
/// page. A tab read recently enough (`staleAfter`) now opens from here and runs nothing
/// at all; an older one opens from here too, and only its newest page or two are read
/// behind it and spliced on top (`ListingMerge`) — never the whole channel again. The
/// Refresh button does the same on demand. See `Scraper.start`.
///
/// One small file per channel tab rather than one big file, so a deep scroll through
/// one channel does not rewrite every other channel with it.
@MainActor
final class ListingCache {
    struct Entry: Codable {
        var videos: [Video]
        var channel: String
        var channelRef: Channel?
        /// When yt-dlp last read the head of this tab — not when it was last paged.
        var stored: Date
        /// Where paging stopped, so "Load more" carries on after a relaunch: the tab URL
        /// that answered and how far into it the walk had got. Nil in entries written
        /// before they were kept, which are treated as stale and so read afresh.
        var resolvedURL: String?
        var cursor: Int?
        var exhausted: Bool?
    }

    static let shared = ListingCache()

    /// Older than this, a list is refreshed behind itself when opened, and the saved
    /// channels are refreshed in the background.
    static let staleAfter: TimeInterval = 4 * 3600
    /// A long scroll back, and still well under a megabyte a file.
    private let keepVideos = 1000

    private let directory: URL = {
        let url = Paths.support.appendingPathComponent("listings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    /// What has been read from disk this launch, so a file is decoded once.
    private var loaded: [String: Entry] = [:]

    private init() {
        migrate()
    }

    static func key(url: String, tab: ChannelTab) -> String {
        var url = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while url.hasSuffix("/") { url.removeLast() }
        for scheme in ["https://", "http://"] where url.hasPrefix(scheme) {
            url.removeFirst(scheme.count)
        }
        if url.hasPrefix("www.") { url.removeFirst(4) }
        return "\(tab.rawValue)|\(url)"
    }

    func entry(for key: String) -> Entry? {
        if let entry = loaded[key] { return entry }
        guard let data = try? Data(contentsOf: file(key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        loaded[key] = entry
        return entry
    }

    /// Read recently enough to open as it is, without asking yt-dlp anything.
    func isFresh(_ key: String, within age: TimeInterval = staleAfter) -> Bool {
        guard let entry = entry(for: key), entry.cursor != nil else { return false }
        return Date.now.timeIntervalSince(entry.stored) < age
    }

    func store(_ entry: Entry, for key: String) {
        guard !entry.videos.isEmpty else { return }
        var entry = entry
        if entry.videos.count > keepVideos {
            entry.videos = Array(entry.videos.prefix(keepVideos))
            // Paging resumes from the cut, not from wherever the walk had got to.
            entry.cursor = min(entry.cursor ?? keepVideos, keepVideos)
        }
        loaded[key] = entry
        let file = file(key)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(entry) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    /// A key is a URL, so the filename is its hash rather than the key itself.
    private func file(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }

    /// The single `listing-cache.json` this replaced, split into a file per entry once.
    private func migrate() {
        let old = Paths.support.appendingPathComponent("listing-cache.json")
        guard let data = try? Data(contentsOf: old) else { return }
        if let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            for (key, value) in saved where self.entry(for: key) == nil { store(value, for: key) }
        }
        try? FileManager.default.removeItem(at: old)
    }
}
