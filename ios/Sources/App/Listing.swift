import Foundation

/// One channel's tab, paged.
///
/// Replaces the Mac app's `Core/Scraper.swift`. There, paging is `--playlist-items
/// N:M` against a fresh yt-dlp process per page; here it is InnerTube's own continuation
/// token, which is both faster and the thing YouTube actually intends — one page is one
/// request, and the token for the next arrives with it.
///
/// Kept-first: a tab read before opens from `ChannelCache` with no request at all, and
/// YouTube is asked only for what is new — on a pull to refresh, or by itself behind the
/// list once that list is older than `ChannelCache.staleAfter`.
@MainActor
@Observable
final class Listing {
    private(set) var channel: Channel?
    private(set) var videos: [Video] = []
    private(set) var isLoading = false
    /// Asking YouTube for new videos behind a list that is already on screen.
    private(set) var isRefreshing = false
    private(set) var error: String?
    /// Nil once the tab is exhausted, which is what stops the infinite scroll.
    private(set) var continuation: String?
    /// When the list on screen last heard from YouTube. Nil until it has been read once.
    private(set) var refreshed: Date?
    /// The last refresh's count of new videos, for the line under the tabs. Nil when no
    /// refresh has run since the list opened.
    private(set) var added: Int?

    private(set) var tab: ChannelTab = .videos
    private var browseID: String?
    private var task: Task<Void, Never>?

    var hasResults: Bool { !videos.isEmpty }
    var canLoadMore: Bool { continuation != nil && !isLoading }

    func reset() {
        task?.cancel()
        task = nil
        channel = nil
        videos = []
        continuation = nil
        error = nil
        isLoading = false
        isRefreshing = false
        refreshed = nil
        added = nil
        browseID = nil
    }

    func stop() {
        task?.cancel()
        task = nil
        isLoading = false
        isRefreshing = false
    }

    /// Open a channel, or switch the tab on the one already open.
    ///
    /// `known` is what the caller already knows about the channel — a search hit or a
    /// saved favourite carries the avatar and subscriber count, and showing them at once
    /// beats a header that pops in a second later.
    func open(_ input: String, known: Channel? = nil, tab: ChannelTab? = nil) {
        task?.cancel()
        if let tab { self.tab = tab }
        videos = []
        continuation = nil
        error = nil
        refreshed = nil
        added = nil
        isRefreshing = false
        channel = known
        isLoading = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                // A `UC…` id resolves without a request, which is every saved channel.
                let id = try await YouTubeAPI.resolveChannel(from: input)
                try Task.checkCancellation()
                self.browseID = id

                if let kept = ChannelCache.shared.entry(channelID: id, tab: self.tab) {
                    self.show(kept, known: known)
                    self.isLoading = false
                    if ChannelCache.shared.isStale(channelID: id, tab: self.tab) {
                        try await self.refreshHead(id: id, tab: self.tab, known: known)
                    }
                    return
                }

                let entry = try await Self.read(browseID: id, tab: self.tab, onto: nil)
                try Task.checkCancellation()
                ChannelCache.shared.store(entry, channelID: id, tab: self.tab)
                self.show(entry, known: known)
                self.isLoading = false
            } catch is CancellationError {
                // A new open replaced this one; it owns the state now.
            } catch {
                self.fail(error)
            }
        }
    }

    /// Switch tabs without re-resolving the channel.
    func show(_ tab: ChannelTab) {
        guard tab != self.tab else { return }
        self.tab = tab
        guard let browseID else { return }
        open(browseID, known: channel, tab: tab)
    }

    /// Ask YouTube for anything new on the tab that is open. What is on screen stays on
    /// screen while it asks, and the new videos land on top.
    func refresh() async {
        // Already asking — the one in flight is the answer, so wait for it rather than
        // start a second.
        if isRefreshing || isLoading {
            await task?.value
            return
        }
        // Nothing on screen (the first read failed): refreshing is trying again.
        guard let browseID, !videos.isEmpty else {
            guard let id = browseID ?? channel?.id else { return }
            open(id, known: channel)
            await task?.value
            return
        }
        isLoading = false
        let tab = self.tab
        let known = channel
        let work = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.refreshHead(id: browseID, tab: tab, known: known)
            } catch is CancellationError {
            } catch {
                self.fail(error)
            }
        }
        task = work
        // Awaited so a pull to refresh holds its spinner until the list has moved.
        await work.value
    }

    /// The next page, triggered by the list reaching its end.
    ///
    /// A kept list's token may be days old, and YouTube's do expire. When one fails the
    /// tab is walked again from the top, past everything already here, which costs a few
    /// requests once and hands back a fresh token for the pages after.
    func loadMore() {
        guard let token = continuation, let browseID, !isLoading else { return }
        isLoading = true
        let channel = channel
        let tab = self.tab

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let page: YouTubeAPI.Page
                do {
                    page = try await YouTubeAPI.continueListing(token: token, channel: channel)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    page = try await Self.walk(browseID: browseID, tab: tab, channel: channel,
                                               past: self.videos)
                }
                try Task.checkCancellation()
                // De-duplicate: YouTube occasionally repeats an item across a page
                // boundary, and a repeated id in a ForEach is a runtime complaint.
                let known = Set(self.videos.map(\.id))
                self.videos += page.videos.filter { !known.contains($0.id) }
                self.continuation = page.continuation
                self.isLoading = false
                self.keep(browseID: browseID, tab: tab)
            } catch is CancellationError {
            } catch {
                // A failed page is not a failed listing — what is already on screen
                // stays, and the footer stops asking for more.
                self.continuation = nil
                self.isLoading = false
            }
        }
    }

    // MARK: - Reading

    private func refreshHead(id: String, tab: ChannelTab, known: Channel?) async throws {
        isRefreshing = true
        defer { isRefreshing = false }
        let before = Set(videos.map(\.id))
        let kept = ChannelCache.shared.entry(channelID: id, tab: tab)
        let entry = try await Self.read(browseID: id, tab: tab, onto: kept)
        try Task.checkCancellation()
        ChannelCache.shared.store(entry, channelID: id, tab: tab)
        show(entry, known: known ?? channel)
        added = entry.videos.filter { !before.contains($0.id) }.count
    }

    private func show(_ entry: ChannelCache.Entry, known: Channel?) {
        // Keep whatever the caller already knew and fold the page's header over it, so a
        // saved channel's avatar survives a listing that has none and a fresh subscriber
        // count still wins where the page has one.
        if var merged = known {
            if let fresh = entry.channel {
                merged.apply(Channel.Details(
                    avatar: fresh.avatar, subscribers: fresh.subscribers,
                    handle: fresh.handle, title: fresh.title))
            }
            channel = merged
        } else {
            channel = entry.channel
        }
        videos = entry.videos
        continuation = entry.continuation
        refreshed = entry.refreshed
        error = nil
    }

    /// Write what is on screen back, after a page has been added to it.
    private func keep(browseID: String, tab: ChannelTab) {
        guard let refreshed else { return }
        ChannelCache.shared.store(
            .init(videos: videos, continuation: continuation, channel: channel,
                  refreshed: refreshed),
            channelID: browseID, tab: tab)
    }

    private func fail(_ error: Error) {
        isLoading = false
        isRefreshing = false
        // A refresh that fails leaves the kept list up: offline is no reason to take it
        // away. Only an empty screen says why it is empty.
        if videos.isEmpty { self.error = error.localizedDescription }
    }

    /// The head of a tab, spliced onto what was kept, as the entry to keep next.
    ///
    /// With nothing kept it is just the first page. Otherwise it reads on, a page at a
    /// time, until the head reaches a video already kept — a channel that posted forty
    /// videos since last time needs two pages, not one — and gives up after a few,
    /// starting the list over from the head rather than leave a hole in it.
    static func read(browseID: String, tab: ChannelTab,
                     onto kept: ChannelCache.Entry?) async throws -> ChannelCache.Entry {
        let first = try await YouTubeAPI.listChannelTab(browseID: browseID, tab: tab)
        var head = first.videos
        var token = first.continuation
        let channel = first.channel ?? kept?.channel

        guard let kept, !kept.videos.isEmpty else {
            return .init(videos: head, continuation: token, channel: channel, refreshed: .now)
        }
        for _ in 0..<4 {
            if let spliced = ListingMerge.splice(head, onto: kept.videos) {
                return .init(videos: spliced.videos, continuation: kept.continuation,
                             channel: channel, refreshed: .now)
            }
            guard let next = token else { break }
            try Task.checkCancellation()
            let page = try await YouTubeAPI.continueListing(token: next, channel: channel)
            let seen = Set(head.map(\.id))
            head += page.videos.filter { !seen.contains($0.id) }
            token = page.continuation
        }
        return .init(videos: head, continuation: token, channel: channel, refreshed: .now)
    }

    /// The page after `past`, found by walking the tab from the top to its last video —
    /// for when the kept token has expired. Bounded, so a channel that has reshuffled
    /// cannot keep it going; nil-handed, the footer just stops.
    private static func walk(browseID: String, tab: ChannelTab, channel: Channel?,
                             past known: [Video]) async throws -> YouTubeAPI.Page {
        guard let anchor = known.last?.id else { return .init(videos: [], continuation: nil) }
        let knownIDs = Set(known.map(\.id))
        var page = try await YouTubeAPI.listChannelTab(browseID: browseID, tab: tab)
        var reached = false
        for _ in 0..<(known.count / 20 + 4) {
            var after = page.videos[...]
            if !reached, let index = page.videos.firstIndex(where: { $0.id == anchor }) {
                reached = true
                after = page.videos[(index + 1)...]
            }
            if reached {
                let fresh = after.filter { !knownIDs.contains($0.id) }
                if !fresh.isEmpty || page.continuation == nil {
                    return .init(videos: Array(fresh), continuation: page.continuation)
                }
            }
            guard let token = page.continuation else { break }
            try Task.checkCancellation()
            page = try await YouTubeAPI.continueListing(token: token, channel: channel)
        }
        return .init(videos: [], continuation: nil)
    }
}
