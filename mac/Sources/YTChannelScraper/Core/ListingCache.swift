import Foundation

/// The last listing each channel tab gave, so opening it again is instant.
///
/// A channel is read by walking it with yt-dlp, which takes seconds even for the first
/// page — and opening a saved channel from the drawer did that from nothing every time.
/// With this, the last list goes on screen at once and the walk happens behind it; see
/// `Scraper.start`. Kept on disk as well, so it survives a relaunch: the channels you
/// keep are the ones you open again.
///
/// Stale by design, and harmless when it is: it is only ever shown while a fresh read is
/// already under way, and the fresh read replaces it.
@MainActor
final class ListingCache {
    struct Entry: Codable {
        var videos: [Video]
        var channel: String
        var channelRef: Channel?
        var stored: Date
    }

    static let shared = ListingCache()

    /// Enough to fill the screen and a scroll or two, not the whole catalogue.
    private let keepVideos = 200
    /// The most recently read, and no more: this is a convenience, not an archive.
    private let keepEntries = 80

    private var entries: [String: Entry] = [:]
    private let file = Paths.support.appendingPathComponent("listing-cache.json")

    private init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
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

    func entry(for key: String) -> Entry? { entries[key] }

    /// Read recently enough that warming it again would only cost a yt-dlp run.
    func isFresh(_ key: String, within age: TimeInterval) -> Bool {
        guard let stored = entries[key]?.stored else { return false }
        return Date.now.timeIntervalSince(stored) < age
    }

    func store(_ videos: [Video], channel: String, channelRef: Channel?, for key: String) {
        guard !videos.isEmpty else { return }
        entries[key] = Entry(videos: Array(videos.prefix(keepVideos)), channel: channel,
                             channelRef: channelRef, stored: .now)
        if entries.count > keepEntries {
            let oldest = entries.sorted { $0.value.stored < $1.value.stored }
                .prefix(entries.count - keepEntries).map(\.key)
            oldest.forEach { entries[$0] = nil }
        }
        save()
    }

    private func save() {
        let snapshot = entries
        let file = self.file
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }
}
