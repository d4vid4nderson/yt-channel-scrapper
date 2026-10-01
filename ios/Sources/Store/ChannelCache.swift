import Foundation

/// Each channel tab as it was last read, kept on the phone.
///
/// Opening a channel used to ask YouTube for it every time, and switching tabs asked
/// again. Now the kept list goes on screen at once with no request at all; YouTube is
/// asked only when the list is older than `staleAfter`, or when someone pulls to refresh
/// — and then only for its newest page or two, spliced on top (`ListingMerge`). Scrolling
/// past the end still pages further back, and what that brings in is kept too.
///
/// One small file per channel tab rather than one big file, so keeping a deep scroll
/// through one channel does not rewrite every other channel with it. Application
/// Support, not Caches: iOS empties Caches under pressure, and these are meant to be
/// there next time without a network.
@MainActor
final class ChannelCache {
    struct Entry: Codable {
        var videos: [Video]
        /// Where the next page starts, past the last kept video. YouTube's tokens do go
        /// stale, so a failure here is expected now and then; see `Listing.loadMore`.
        var continuation: String?
        var channel: Channel?
        /// When YouTube was last asked for the head of this tab.
        var refreshed: Date
    }

    static let shared = ChannelCache()

    /// Older than this, a list is refreshed behind itself when opened, and the saved
    /// channels are refreshed in the background.
    static let staleAfter: TimeInterval = 4 * 3600
    /// Enough for a long scroll back, small enough that a file stays well under a
    /// megabyte.
    private let keepVideos = 1000

    private let directory: URL = {
        let url = Paths.support.appendingPathComponent("listings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    /// What has been read from disk this launch, so a file is decoded once.
    private var loaded: [String: Entry] = [:]

    private init() {}

    func entry(channelID: String, tab: ChannelTab) -> Entry? {
        let key = Self.key(channelID, tab)
        if let entry = loaded[key] { return entry }
        guard let data = try? Data(contentsOf: file(key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        loaded[key] = entry
        return entry
    }

    func isStale(channelID: String, tab: ChannelTab) -> Bool {
        guard let entry = entry(channelID: channelID, tab: tab) else { return true }
        return Date.now.timeIntervalSince(entry.refreshed) > Self.staleAfter
    }

    func store(_ entry: Entry, channelID: String, tab: ChannelTab) {
        guard !entry.videos.isEmpty else { return }
        var entry = entry
        if entry.videos.count > keepVideos {
            entry.videos = Array(entry.videos.prefix(keepVideos))
            // The token points past the end of what was cut, so it would skip a gap.
            // A thousand back is deep enough to call the end of the list.
            entry.continuation = nil
        }
        let key = Self.key(channelID, tab)
        loaded[key] = entry
        let file = file(key)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(entry) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    private static func key(_ channelID: String, _ tab: ChannelTab) -> String {
        "\(channelID)-\(tab.rawValue)"
    }

    private func file(_ key: String) -> URL {
        directory.appendingPathComponent(key + ".json")
    }
}
