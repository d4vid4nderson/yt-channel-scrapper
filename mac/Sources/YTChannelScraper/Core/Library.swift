import Foundation

/// The things you keep: channels to come back to, and individual videos to come back
/// for. Two flat JSON files next to the app's other state, rewritten on every change —
/// these are tens of entries, not thousands, so there is nothing to be gained by being
/// cleverer about it.
@MainActor
@Observable
final class Library {
    /// Held sorted by title, because the shelf is something you scan rather than a feed:
    /// once a Takeout import has put 200 channels in it, alphabetical is the only order
    /// you can find anything in.
    private(set) var channels: [Channel] = []

    /// Newest first — a saved video is a thing you meant to come back to shortly, so
    /// recency is the order that matters.
    private(set) var videos: [Video] = []

    /// What the last import did, shown next to the shelf. Cleared by the next one.
    private(set) var note: String?

    private static var channelsFile: URL { Paths.support.appendingPathComponent("channels.json") }
    private static var videosFile: URL { Paths.support.appendingPathComponent("saved-videos.json") }

    private var resolving: Set<String> = []
    private var resolver: Task<Void, Never>?

    /// A tuple here trips the region-based isolation checker, so the pair crossing back
    /// out of the task group is a named type.
    private struct Resolved: Sendable {
        let id: String
        let details: Channel.Details?
    }

    init() {
        channels = Self.read([Channel].self, from: Self.channelsFile) ?? []
        videos = Self.read([Video].self, from: Self.videosFile) ?? []
        fillInAvatars()
    }

    var isEmpty: Bool { channels.isEmpty }

    /// The shelf's order: what you reached for most recently, then what you starred most
    /// recently. Alphabetical is right for a list you scan for a known name and wrong for
    /// a shelf of six — there, the six should be the six you actually use.
    var recent: [Channel] {
        channels.sorted { lhs, rhs in
            let left = lhs.lastOpenedAt ?? lhs.savedAt ?? .distantPast
            let right = rhs.lastOpenedAt ?? rhs.savedAt ?? .distantPast
            guard left == right else { return left > right }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func markOpened(_ id: String) {
        guard let index = channels.firstIndex(where: { $0.id == id }) else { return }
        channels[index].lastOpenedAt = Date()
        persistChannels()
    }

    /// Say what just happened, next to the shelf.
    func report(_ message: String?) { note = message }

    // MARK: - Channels

    func contains(_ id: String) -> Bool { channels.contains { $0.id == id } }

    func toggle(_ channel: Channel) {
        contains(channel.id) ? remove(channel.id) : add(channel)
    }

    /// Re-saving a channel refreshes it rather than duplicating: a hit from search knows
    /// the subscriber count and the avatar, and one saved from a scrape does not, so the
    /// richer record should win.
    func add(_ channel: Channel) {
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            var merged = channel
            merged.handle = channel.handle ?? channels[index].handle
            merged.subscribers = channel.subscribers ?? channels[index].subscribers
            merged.avatar = channel.avatar ?? channels[index].avatar
            channels[index] = merged
        } else {
            channels.append(channel)
        }
        sortChannels()
        persistChannels()
        fillInAvatars()
    }

    func remove(_ id: String) {
        channels.removeAll { $0.id == id }
        note = nil
        persistChannels()
    }

    // MARK: - Videos

    func containsVideo(_ id: String) -> Bool { videos.contains { $0.id == id } }

    func toggleVideo(_ video: Video, channel: Channel?, channelName: String?) {
        if containsVideo(video.id) {
            removeVideo(video.id)
        } else {
            var saved = video
            // A scrape's entries already carry the channel, but one opened from a
            // playlist may not, and the header knows it either way.
            saved.channelName = saved.channelName ?? channel?.title ?? channelName
            saved.channelId = saved.channelId ?? channel?.id
            videos.insert(saved, at: 0)
            persistVideos()
        }
    }

    func removeVideo(_ id: String) {
        videos.removeAll { $0.id == id }
        persistVideos()
    }

    // MARK: - Avatars

    /// Fill in the pictures for channels that arrived without one.
    ///
    /// A channel saved from a scrape and a row imported from Takeout both know only an
    /// id and a name, and a channel's own page costs a full request (~5s) to read — so
    /// this runs quietly in the background, two at a time, and what it learns is written
    /// down. It is a one-off per channel, not a per-launch cost.
    func fillInAvatars() {
        guard resolver == nil else { return }
        resolver = Task { [weak self] in
            defer { self?.resolver = nil }
            while let batch = self?.nextToResolve(), !batch.isEmpty {
                let resolved = await withTaskGroup(of: Resolved.self) { group in
                    for channel in batch {
                        group.addTask {
                            Resolved(id: channel.id, details: await Self.fetchDetails(for: channel))
                        }
                    }
                    var all: [Resolved] = []
                    for await one in group { all.append(one) }
                    return all
                }
                guard let self else { return }
                for one in resolved {
                    self.resolving.remove(one.id)
                    guard let details = one.details,
                          let index = self.channels.firstIndex(where: { $0.id == one.id })
                    else { continue }
                    self.channels[index].apply(details)
                }
                self.persistChannels()
                if Task.isCancelled { return }
            }
        }
    }

    /// Two at a time: enough that a Takeout import fills in at a reasonable pace,
    /// restrained enough not to look like a crawler.
    private func nextToResolve() -> [Channel] {
        let batch = channels
            .filter { $0.needsDetails && !resolving.contains($0.id) }
            .prefix(2)
        for channel in batch { resolving.insert(channel.id) }
        return Array(batch)
    }

    private static func fetchDetails(for channel: Channel) async -> Channel.Details? {
        let stream = ProcessStream(
            executable: Paths.ytdlp,
            arguments: YtDlp.channelDetailsArguments(url: channel.url),
            environment: YtDlp.environment
        )
        var payload = ""
        do {
            // --dump-single-json prints the whole channel object as one line.
            for try await line in stream.lines() where line.hasPrefix("{") {
                payload = line
                break
            }
        } catch {
            return nil     // a channel that will not open keeps its initials
        }
        stream.terminate()
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return Channel.details(fromJSON: json)
    }

    // MARK: - Takeout

    /// Read a Google Takeout `subscriptions.csv`.
    ///
    /// Takeout is the way to get a real subscription list in here without an OAuth
    /// client and Google's app review: YouTube exports one file, and every channel in it
    /// lands as a saved channel. It is a snapshot rather than a live feed — re-importing
    /// later merges rather than duplicates, so catching up is just importing again.
    @discardableResult
    func importTakeout(from url: URL) throws -> Int {
        let text = try String(contentsOf: url, encoding: .utf8)
        let added = importTakeout(csv: text)
        note = added > 0
            ? "Imported \(added) channel\(added == 1 ? "" : "s") — pictures are loading in the background."
            : "No channels found in \(url.lastPathComponent) — is that the subscriptions.csv?"
        return added
    }

    /// Columns are read by position, not by name: Takeout localises its headers, so
    /// "Channel ID" is only "Channel ID" for an account set to English. Position is the
    /// same in every locale — id, url, title.
    @discardableResult
    func importTakeout(csv: String) -> Int {
        var found: [Channel] = []
        for line in csv.split(whereSeparator: \.isNewline) {
            let fields = Self.csvFields(String(line))
            guard let id = fields.first?.trimmingCharacters(in: .whitespaces),
                  id.hasPrefix("UC"), id.count > 10
            else { continue }   // the header row, and any blank or malformed line
            let title = fields.count > 2 ? fields[2].trimmingCharacters(in: .whitespaces) : id
            found.append(Channel(id: id, title: title.isEmpty ? id : title))
        }

        guard !found.isEmpty else { return 0 }
        let fresh = found.filter { !contains($0.id) }.count
        for channel in found {
            if let index = channels.firstIndex(where: { $0.id == channel.id }) {
                // An imported row carries only id and title, so it must not overwrite an
                // avatar and subscriber count already learned from search.
                channels[index].title = channel.title
            } else {
                channels.append(channel)
            }
        }
        sortChannels()
        persistChannels()
        fillInAvatars()
        return fresh
    }

    /// Split one CSV row. Titles routinely contain commas, so quoted fields have to be
    /// respected; `""` inside a quoted field is an escaped quote.
    static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        fields.append(current)
        return fields
    }

    // MARK: - Disk

    private func sortChannels() {
        channels.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func read<T: Decodable>(_ type: T.Type, from file: URL) -> T? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persistChannels() { write(channels, to: Self.channelsFile) }
    private func persistVideos() { write(videos, to: Self.videosFile) }

    private func write<T: Encodable>(_ value: T, to file: URL) {
        do {
            try JSONEncoder().encode(value).write(to: file, options: .atomic)
        } catch {
            Log.library.error(
                "could not write \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
