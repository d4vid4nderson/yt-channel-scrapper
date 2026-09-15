import Foundation

/// The things you keep: channels to come back to, and individual videos to come back
/// for. Two flat JSON files, rewritten on every change — these are tens of entries, not
/// thousands, so there is nothing to be gained by being cleverer about it.
///
/// A port of the Mac app's `Core/Library.swift` rather than a shared copy of it: that
/// file resolves a channel's avatar by running yt-dlp, which cannot compile here. The
/// **on-disk format is deliberately identical**, so a `.ytcslibrary` exported on the Mac
/// opens here and vice versa — `LibraryArchive` itself is shared, unmodified.
@MainActor
@Observable
final class Library {
    /// Held sorted by title, because the shelf is something you scan: once a Takeout
    /// import has put 200 channels in it, alphabetical is the only order you can find
    /// anything in.
    private(set) var channels: [Channel] = []

    /// Newest first — a saved video is a thing you meant to come back to shortly, so
    /// recency is the order that matters.
    private(set) var videos: [Video] = []

    /// What the last import or export did. Cleared by the next one.
    private(set) var note: String?

    private static var channelsFile: URL { Paths.support.appendingPathComponent("channels.json") }
    private static var videosFile: URL { Paths.support.appendingPathComponent("saved-videos.json") }

    private var resolving: Set<String> = []
    private var resolver: Task<Void, Never>?

    /// The copy that outlives the app. Deleting an app takes Application Support with
    /// it, so without this a reinstall starts empty — which is exactly what happened.
    let cloud = CloudMirror()

    init() {
        channels = Self.read([Channel].self, from: Self.channelsFile) ?? []
        videos = Self.read([Video].self, from: Self.videosFile) ?? []

        // Set before `start()`, because the first read can hand something back
        // synchronously and there would be nothing listening.
        cloud.didReceive = { [weak self] incoming in self?.adopt(incoming) }
        cloud.start()
        // Seeds iCloud from a library that predates it. Harmless when iCloud is already
        // newer: `start()` will have adopted that first, and this then pushes the same
        // thing back.
        if !isEmpty || !videos.isEmpty { mirror() }

        fillInAvatars()
    }

    /// Take iCloud's copy wholesale — see `CloudMirror` for why this replaces rather
    /// than merges. Written straight to disk without pushing back: this *is* what iCloud
    /// already holds, so echoing it would be a write for nothing.
    private func adopt(_ archive: LibraryArchive) {
        channels = archive.channels
        videos = archive.videos
        sortChannels()
        write(channels, to: Self.channelsFile)
        write(videos, to: Self.videosFile)
        fillInAvatars()
    }

    /// Hand the current state to iCloud. Called from both persist paths, so every change
    /// that reaches disk reaches the mirror too.
    private func mirror() { cloud.push(archive(.both)) }

    var isEmpty: Bool { channels.isEmpty }

    /// The shelf's order: what you reached for most recently, then what you bookmarked most
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

    func report(_ message: String?) { note = message }

    // MARK: - Channels

    func contains(_ id: String) -> Bool { channels.contains { $0.id == id } }

    func toggle(_ channel: Channel) {
        contains(channel.id) ? remove(channel.id) : add(channel)
    }

    /// Re-saving a channel refreshes it rather than duplicating: a hit from search knows
    /// the subscriber count and the avatar, one saved from a listing does not, so the
    /// richer record wins.
    func add(_ channel: Channel) {
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            var merged = channel
            merged.handle = channel.handle ?? channels[index].handle
            merged.subscribers = channel.subscribers ?? channels[index].subscribers
            merged.avatar = channel.avatar ?? channels[index].avatar
            merged.savedAt = channels[index].savedAt ?? merged.savedAt
            merged.lastOpenedAt = channels[index].lastOpenedAt
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

    func toggleVideo(_ video: Video, channel: Channel?) {
        if containsVideo(video.id) {
            removeVideo(video.id)
        } else {
            var saved = video
            saved.channelName = saved.channelName ?? channel?.title
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
    /// A channel saved from a listing and a row imported from Takeout both know only an
    /// id and a name, and a channel's own page costs a request to read — so this runs
    /// quietly in the background, two at a time, and what it learns is written down.
    /// One-off per channel, not a per-launch cost.
    func fillInAvatars() {
        guard resolver == nil else { return }
        resolver = Task { [weak self] in
            while let batch = self?.nextToResolve(), !batch.isEmpty {
                await withTaskGroup(of: Resolved.self) { group in
                    for channel in batch {
                        group.addTask {
                            Resolved(id: channel.id,
                                     details: try? await YouTubeAPI.details(for: channel.id))
                        }
                    }
                    for await resolved in group {
                        self?.apply(resolved)
                    }
                }
            }
            self?.resolver = nil
        }
    }

    /// A tuple trips the region-based isolation checker, so the pair crossing back out
    /// of the task group is a named type.
    private struct Resolved: Sendable {
        let id: String
        let details: Channel.Details?
    }

    private func apply(_ resolved: Resolved) {
        resolving.remove(resolved.id)
        guard let details = resolved.details,
              let index = channels.firstIndex(where: { $0.id == resolved.id })
        else { return }
        channels[index].apply(details)
        persistChannels()
    }

    private func nextToResolve() -> [Channel] {
        let batch = channels
            .filter { $0.needsDetails && !resolving.contains($0.id) }
            .prefix(2)
        for channel in batch { resolving.insert(channel.id) }
        return Array(batch)
    }

    // MARK: - Takeout

    /// Read a Google Takeout `subscriptions.csv`, picked in the Files app.
    ///
    /// Takeout is the way to get a real subscription list in here without an OAuth
    /// client and Google's app review: YouTube exports one file and every channel in it
    /// lands as a saved channel. A snapshot rather than a live feed — re-importing later
    /// merges rather than duplicates, so catching up is just importing again.
    @discardableResult
    func importTakeout(from url: URL) throws -> Int {
        // A file handed over by the document picker lives outside the sandbox and has to
        // be opened under a security scope, which the Mac's version has no need of.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return importTakeout(csv: try String(contentsOf: url, encoding: .utf8))
    }

    @discardableResult
    func importTakeout(csv: String) -> Int {
        var found: [Channel] = []
        for line in csv.split(whereSeparator: \.isNewline).dropFirst() {
            let fields = Self.csvFields(String(line))
            // Channel ID, Channel URL, Channel Title.
            guard fields.count >= 3 else { continue }
            let id = fields[0].trimmingCharacters(in: .whitespaces)
            guard id.hasPrefix("UC") else { continue }
            let title = fields[2].trimmingCharacters(in: .whitespaces)
            found.append(Channel(id: id, title: title.isEmpty ? id : title))
        }

        let before = channels.count
        for channel in found where !contains(channel.id) {
            channels.append(channel)
        }
        sortChannels()
        persistChannels()
        fillInAvatars()

        let added = channels.count - before
        note = found.isEmpty
            ? "No channels found in that file — is it subscriptions.csv?"
            : "Imported \(added) new channel\(added == 1 ? "" : "s") of \(found.count)."
        return added
    }

    /// Split one CSV line, honouring quoted fields with commas in them.
    static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")     // an escaped quote inside a quoted field
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if character == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }

    // MARK: - Transfer

    /// Which halves of the library a transfer carries.
    ///
    /// The two lists answer different questions — the channels are the shelf somebody
    /// browses, the videos are a specific set of things to watch — and there are real
    /// reasons to move one without the other. Sending a minor's phone a handful of
    /// approved videos should not also hand them two hundred channels to roam.
    enum Contents: String, CaseIterable, Identifiable, Sendable {
        case both
        case channels
        case videos

        var id: String { rawValue }

        var hasChannels: Bool { self != .videos }
        var hasVideos: Bool { self != .channels }

        /// For the segmented picker, where the column is narrow.
        var short: String {
            switch self {
            case .both:     "Both"
            case .channels: "Channels"
            case .videos:   "Videos"
            }
        }

        /// For a menu, where it has to say what it will do on its own.
        var menuLabel: String {
            switch self {
            case .both:     "Channels and Videos"
            case .channels: "Channels Only"
            case .videos:   "Videos Only"
            }
        }

        var icon: String {
            switch self {
            case .both:     "square.stack"
            case .channels: "person.2"
            case .videos:   "play.rectangle"
            }
        }
    }

    /// An archive of exactly these entries, for handing somebody a chosen subset rather
    /// than the whole shelf.
    ///
    /// Channels and videos are picked independently and neither drags the other in. That
    /// is the point: a channel grants everything in it, including whatever it uploads
    /// next, while a video grants one video and nothing else — so quietly adding a
    /// video's channel alongside it would hand over far more than was ticked.
    func archive(channelIDs: Set<String>, videoIDs: Set<String>) -> LibraryArchive {
        LibraryArchive(channels: channels.filter { channelIDs.contains($0.id) },
                       videos: videos.filter { videoIDs.contains($0.id) })
    }

    func archive(_ contents: Contents) -> LibraryArchive {
        LibraryArchive(channels: contents.hasChannels ? channels : [],
                       videos: contents.hasVideos ? videos : [])
    }

    /// Whether there is anything to send under that choice. An export that would write
    /// two empty lists is a file that does nothing on the far side.
    func canExport(_ contents: Contents) -> Bool {
        (contents.hasChannels && !channels.isEmpty) || (contents.hasVideos && !videos.isEmpty)
    }

    func export(_ contents: Contents, to url: URL) throws {
        let written = archive(contents)
        try written.write(to: url)
        note = "Exported \(Self.summary(of: written))."
    }

    /// Read one without changing anything, so the import sheet can say what is in the
    /// file before any of it is taken.
    ///
    /// A file handed over by the document picker lives outside the sandbox and has to be
    /// opened under a security scope, which the Mac's version has no need of. The whole
    /// archive comes back in memory, which also means the merge that follows needs no
    /// second visit to a URL whose scope may since have lapsed.
    static func read(from url: URL) throws -> LibraryArchive {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try LibraryArchive.read(from: url)
    }

    /// Take some or all of an archive into this library.
    ///
    /// Channels merge through `add`, so a richer incoming record refreshes a thinner
    /// saved one rather than duplicating it. Videos are appended in the order they
    /// arrive, **after** what is already here: the shelf is newest-first and somebody
    /// else's export is not news, so it should not push its way to the top. Re-importing
    /// the same file therefore changes nothing, which is what makes "send an updated one
    /// later" a safe thing to tell people to do.
    @discardableResult
    func merge(_ incoming: LibraryArchive, contents: Contents) -> String {
        let channelsBefore = channels.count
        let videosBefore = videos.count

        if contents.hasChannels {
            for channel in incoming.channels { add(channel) }
        }
        if contents.hasVideos {
            for video in incoming.videos where !containsVideo(video.id) {
                videos.append(video)
            }
            persistVideos()
        }

        let message = Self.summary(channels: channels.count - channelsBefore,
                                   videos: videos.count - videosBefore)
        note = message.isEmpty ? "Nothing new — it is all here already." : "Added \(message)."
        return note ?? ""
    }

    /// "12 channels and 3 videos", with the half that is empty left out entirely rather
    /// than written as a zero. Empty when both are.
    static func summary(channels: Int, videos: Int) -> String {
        var parts: [String] = []
        if channels > 0 { parts.append("\(channels) channel\(channels == 1 ? "" : "s")") }
        if videos > 0 { parts.append("\(videos) video\(videos == 1 ? "" : "s")") }
        return parts.joined(separator: " and ")
    }

    static func summary(of archive: LibraryArchive) -> String {
        let text = summary(channels: archive.channels.count, videos: archive.videos.count)
        return text.isEmpty ? "nothing" : text
    }

    // MARK: - Disk

    private func sortChannels() {
        channels.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func read<T: Decodable>(_ type: T.Type, from file: URL) -> T? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persistChannels() {
        write(channels, to: Self.channelsFile)
        mirror()
    }

    private func persistVideos() {
        write(videos, to: Self.videosFile)
        mirror()
    }

    private func write<T: Encodable>(_ value: T, to file: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: file, options: .atomic)
        } catch {
            let detail = "could not write \(file.lastPathComponent): \(error.localizedDescription)"
            Log.library.error("\(detail, privacy: .public)")
        }
    }
}
