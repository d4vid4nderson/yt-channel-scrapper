import Foundation

/// Walks a channel tab and streams videos into `videos`, a page at a time.
///
/// The page boundary matters: a 5,000-video channel should put its first 25 on screen in
/// seconds, not after the whole catalogue has been walked. `--lazy-playlist` plus a
/// bounded `--playlist-items` range does that, and the cursor is what lets the next page
/// pick up where this one stopped.
@MainActor
@Observable
final class Scraper {
    enum Status: Equatable {
        case idle, running, paused, done, stopped, failed
    }

    static let pageSize = 25

    private(set) var status: Status = .idle
    private(set) var videos: [Video] = []
    private(set) var channel = ""
    /// The channel this listing belongs to, so it can be saved from the results bar
    /// without having to be searched for again.
    private(set) var channelRef: Channel?
    private(set) var error: String?

    /// The tab URL that actually answered, kept so "load more" resumes on the same one.
    private var resolvedURL: String?
    /// How many entries of the *outer* listing have been consumed. For Videos/Shorts/Live
    /// that tracks `videos.count`; for Music each entry is an album holding many tracks.
    private var outerCursor = 0
    private var exhausted = false
    private var seen: Set<String> = []
    private var task: Task<Void, Never>?
    private var stream: ProcessStream?

    /// True while a fresh read is walking behind a list shown from `ListingCache`. The
    /// walk collects into `incoming` and swaps it in whole when it settles, so the list
    /// on screen never empties and refills under the reader.
    private(set) var isRefreshing = false
    private var incoming: [Video] = []
    private var cacheKey: String?

    /// The kept list a refresh is reading the head of, so the head can be spliced onto it.
    private var kept: ListingCache.Entry?

    /// What is open, so a tab switch or a Refresh can read it again without the field.
    private(set) var rawURL: String?
    private(set) var tab: ChannelTab = .videos
    /// When the list on screen last heard from YouTube.
    private(set) var refreshed: Date?
    /// What the last refresh brought; nil when none has run since the list opened.
    private(set) var added: Int?

    var canRefresh: Bool { rawURL != nil && status != .running }

    /// What the walk is collecting into — the list on screen, or the one behind it.
    private var collected: [Video] { isRefreshing ? incoming : videos }

    var canLoadMore: Bool { status == .paused }
    var isBusy: Bool { status == .running }

    // MARK: - Control

    func reset() {
        stop()
        isRefreshing = false
        incoming = []
        cacheKey = nil
        kept = nil
        rawURL = nil
        refreshed = nil
        added = nil
        videos = []
        seen = []
        channel = ""
        channelRef = nil
        error = nil
        status = .idle
        resolvedURL = nil
        outerCursor = 0
        exhausted = false
    }

    func stop() {
        task?.cancel()
        task = nil
        stream?.terminate()
        stream = nil
        // Stopping a refresh leaves the cached list up, which is still a real list.
        if isRefreshing {
            isRefreshing = false
            incoming = []
            if status == .running { restoreKept() }
            return
        }
        if status == .running { status = .stopped }
    }

    /// Open a channel tab: from what is kept when it is fresh, from what is kept with its
    /// newest page read behind it when it is not, and from yt-dlp alone when nothing is.
    /// `force` is the Refresh button — read the head however fresh the list is.
    func start(rawURL: String, tab: ChannelTab, force: Bool = false) {
        stop()
        let key = ListingCache.key(url: rawURL, tab: tab)
        self.rawURL = rawURL
        self.tab = tab
        cacheKey = key
        seen = []
        error = nil
        outerCursor = 0
        exhausted = false
        incoming = []
        added = nil
        kept = nil
        let cache = ListingCache.shared
        // Seen before: the last list goes up at once.
        if let cached = cache.entry(for: key) {
            videos = cached.videos
            channel = cached.channel
            channelRef = cached.channelRef
            refreshed = cached.stored
            // Recent enough that nothing needs asking at all.
            if !force, cache.isFresh(key), let cursor = cached.cursor {
                resolvedURL = cached.resolvedURL
                outerCursor = cursor
                exhausted = cached.exhausted ?? false
                seen = Set(videos.map(\.id))
                isRefreshing = false
                status = exhausted || resolvedURL == nil ? .done : .paused
                return
            }
            // Otherwise its head is read behind it.
            kept = cached
            isRefreshing = true
        } else {
            videos = []
            channel = ""
            channelRef = nil
            refreshed = nil
            isRefreshing = false
        }
        status = .running

        task = Task { [weak self] in
            guard let self else { return }
            do {
                for path in tab.paths {
                    let candidate = try YtDlp.channelURL(from: rawURL, path: path)
                    self.resolvedURL = candidate
                    self.outerCursor = 0
                    self.exhausted = false
                    try await self.fill(upTo: Self.pageSize)
                    if !self.collected.isEmpty { break }
                }
                guard !self.collected.isEmpty else { throw YtDlp.Failure.noTab(tab.label) }
                // A refresh reads on until the head reaches a video already kept — forty
                // new since last time is two pages, not one — and gives up at a few,
                // starting the list over rather than leaving a hole in it.
                if self.isRefreshing, let kept = self.kept {
                    while ListingMerge.splice(self.incoming, onto: kept.videos) == nil,
                          !self.exhausted, self.incoming.count < 8 * Self.pageSize {
                        try await self.fill(upTo: self.incoming.count + Self.pageSize)
                    }
                }
                self.settle()
            } catch is CancellationError {
                // stop() already recorded the state
            } catch {
                // A failed refresh keeps the list it was refreshing — offline, or
                // yt-dlp having a bad day, is no reason to take it away.
                if self.isRefreshing {
                    Log.library.error("refresh failed: \(error.localizedDescription, privacy: .public)")
                    self.isRefreshing = false
                    self.incoming = []
                    self.restoreKept()
                } else {
                    self.fail(error)
                }
            }
        }
    }

    /// Read the newest videos of whatever is open, however recently it was read.
    func refresh() {
        guard let rawURL, status != .running else { return }
        start(rawURL: rawURL, tab: tab, force: true)
    }

    /// Back to paging the kept list as it was, after a refresh that did not finish.
    private func restoreKept() {
        guard let kept else { status = .done; return }
        resolvedURL = kept.resolvedURL
        outerCursor = kept.cursor ?? 0
        exhausted = kept.exhausted ?? false
        seen = Set(videos.map(\.id))
        self.kept = nil
        status = exhausted || kept.cursor == nil || resolvedURL == nil ? .done : .paused
    }

    func loadMore() {
        guard status == .paused, resolvedURL != nil else { return }
        status = .running
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.fill(upTo: self.videos.count + Self.pageSize)
                self.settle()
            } catch is CancellationError {
            } catch {
                self.fail(error)
            }
        }
    }

    // MARK: - Walking

    private func settle() {
        guard status == .running else { return }
        if isRefreshing {
            let before = Set(videos.map(\.id))
            if let kept, let spliced = ListingMerge.splice(incoming, onto: kept.videos) {
                videos = spliced.videos
                // Paging carries on where the kept list stopped, moved down by what
                // arrived on top and up by what was taken down. Music's cursor counts
                // albums rather than tracks, so it is left where it was: too early only
                // costs a few repeats, which `seen` drops.
                if let cursor = kept.cursor {
                    let removed = kept.videos.count + spliced.added - spliced.videos.count
                    outerCursor = tab == .music ? cursor : max(0, cursor + spliced.added - removed)
                    exhausted = kept.exhausted ?? false
                    if let url = kept.resolvedURL { resolvedURL = url }
                } else {
                    exhausted = false
                }
            } else {
                videos = incoming
            }
            added = videos.filter { !before.contains($0.id) }.count
            incoming = []
            isRefreshing = false
            kept = nil
            refreshed = .now
        } else if refreshed == nil {
            refreshed = .now
        }
        seen = Set(videos.map(\.id))
        status = exhausted ? .done : .paused
        if let cacheKey {
            ListingCache.shared.store(
                .init(videos: videos, channel: channel, channelRef: channelRef,
                      stored: refreshed ?? .now, resolvedURL: resolvedURL,
                      cursor: outerCursor, exhausted: exhausted),
                for: cacheKey)
        }
    }

    private func fail(_ error: Error) {
        guard status == .running else { return }
        if let known = error as? YtDlp.Failure {
            self.error = known.errorDescription
        } else if let failure = error as? ProcessStream.Failure, !failure.message.isEmpty {
            self.error = "Could not read that channel: " + Self.tidy(failure.message)
        } else {
            self.error = "Could not read that channel: \(error.localizedDescription)"
        }
        status = .failed
    }

    /// yt-dlp's stderr runs to many lines of context; the last ERROR line is the useful one.
    private static func tidy(_ stderr: String) -> String {
        let lines = stderr.split(separator: "\n")
        let line = lines.last(where: { $0.contains("ERROR") }) ?? lines.last ?? ""
        var text = line.replacingOccurrences(of: "ERROR: ", with: "")
        // yt-dlp prefixes its messages with the extractor that raised them, e.g.
        // "[youtube:tab] ..." — noise to anyone who is not debugging yt-dlp.
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = String(text[text.index(after: close)...])
        }
        return String(text.trimmingCharacters(in: .whitespaces).prefix(300))
    }

    private struct Chunk {
        var consumed = 0
        var reachedTarget = false
    }

    /// Pull outer entries until `target` videos are in hand or the listing runs dry.
    private func fill(upTo target: Int) async throws {
        while collected.count < target {
            let chunk = try await pullChunk(target: target)
            if chunk.reachedTarget { return }
            if chunk.consumed < Self.pageSize {
                exhausted = true    // the outer listing had nothing more to give
                return
            }
        }
    }

    /// One pass over a chunk of the outer listing.
    private func pullChunk(target: Int) async throws -> Chunk {
        guard let url = resolvedURL else { return Chunk() }
        let stream = ProcessStream(
            executable: Paths.ytdlp,
            arguments: YtDlp.scrapeArguments(url: url, offset: outerCursor, count: Self.pageSize),
            environment: YtDlp.environment
        )
        self.stream = stream
        defer { self.stream = nil }

        var chunk = Chunk()
        do {
            for try await line in stream.lines() {
                try Task.checkCancellation()
                guard let json = Self.decode(line) else { continue }

                chunk.consumed += 1
                outerCursor += 1
                // A refresh takes the name afresh too: channels do rename.
                if channel.isEmpty || (isRefreshing && chunk.consumed == 1) {
                    let name = (json["playlist_channel"] as? String)
                        ?? (json["playlist_title"] as? String) ?? ""
                    if !name.isEmpty { channel = name }
                }
                if channelRef == nil || (isRefreshing && chunk.consumed == 1),
                   let ref = Channel(listingJSON: json) {
                    channelRef = ref
                }
                await absorb(json, depth: 0)

                if collected.count >= target {
                    chunk.reachedTarget = true
                    stream.terminate()      // page is full; stop walking the channel
                    break
                }
            }
        } catch let failure as ProcessStream.Failure {
            // A tab the channel does not have exits non-zero having printed nothing.
            // With entries already in hand that is just the end of the listing.
            if chunk.consumed == 0 && collected.isEmpty { throw failure }
        }
        return chunk
    }

    /// Turn one flat-playlist entry into videos.
    ///
    /// Most tabs list videos directly, but Music lists albums whose tracks only appear
    /// once the album itself is opened — so nested playlists get expanded, depth-capped
    /// since each one costs a request.
    private func absorb(_ json: [String: Any], depth: Int) async {
        let isPlaylist = (json["ie_key"] as? String) == "YoutubeTab"
            || (json["_type"] as? String) == "playlist"

        guard isPlaylist else {
            if let video = Video(json: json), seen.insert(video.id).inserted {
                if isRefreshing { incoming.append(video) } else { videos.append(video) }
            }
            return
        }

        guard depth < 2, let nested = json["url"] as? String else { return }
        let sub = ProcessStream(
            executable: Paths.ytdlp,
            arguments: YtDlp.scrapeArguments(url: nested, offset: 0, count: 200),
            environment: YtDlp.environment
        )
        do {
            for try await line in sub.lines() {
                if Task.isCancelled { sub.terminate(); return }
                guard let child = Self.decode(line) else { continue }
                await absorb(child, depth: depth + 1)
            }
        } catch {
            // An album that will not open is skipped rather than failing the scrape.
        }
    }

    private static func decode(_ line: String) -> [String: Any]? {
        guard line.hasPrefix("{"), let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
