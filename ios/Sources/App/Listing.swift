import Foundation

/// One channel's tab, paged.
///
/// Replaces the Mac app's `Core/Scraper.swift`. There, paging is `--playlist-items
/// N:M` against a fresh yt-dlp process per page; here it is InnerTube's own continuation
/// token, which is both faster and the thing YouTube actually intends — one page is one
/// request, and the token for the next arrives with it.
@MainActor
@Observable
final class Listing {
    private(set) var channel: Channel?
    private(set) var videos: [Video] = []
    private(set) var isLoading = false
    private(set) var error: String?
    /// Nil once the tab is exhausted, which is what stops the infinite scroll.
    private(set) var continuation: String?

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
        browseID = nil
    }

    func stop() {
        task?.cancel()
        task = nil
        isLoading = false
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
        channel = known
        isLoading = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let id = try await YouTubeAPI.resolveChannel(from: input)
                try Task.checkCancellation()
                self.browseID = id

                let page = try await YouTubeAPI.listChannelTab(browseID: id, tab: self.tab)
                try Task.checkCancellation()

                // Keep whatever the caller already knew and fold the page's header over
                // it, so a saved channel's avatar survives a listing that has none and
                // a fresh subscriber count still wins where the page has one.
                if var merged = known {
                    if let fresh = page.channel {
                        merged.apply(Channel.Details(
                            avatar: fresh.avatar, subscribers: fresh.subscribers,
                            handle: fresh.handle, title: fresh.title))
                    }
                    self.channel = merged
                } else {
                    self.channel = page.channel
                }
                self.videos = page.videos
                self.continuation = page.continuation
                self.isLoading = false
            } catch is CancellationError {
                // A new open replaced this one; it owns the state now.
            } catch {
                self.error = error.localizedDescription
                self.isLoading = false
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

    /// The next page, triggered by the list reaching its end.
    func loadMore() {
        guard let token = continuation, !isLoading else { return }
        isLoading = true
        let channel = channel

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await YouTubeAPI.continueListing(token: token, channel: channel)
                try Task.checkCancellation()
                // De-duplicate: YouTube occasionally repeats an item across a page
                // boundary, and a repeated id in a ForEach is a runtime complaint.
                let known = Set(self.videos.map(\.id))
                self.videos += page.videos.filter { !known.contains($0.id) }
                self.continuation = page.continuation
                self.isLoading = false
            } catch is CancellationError {
            } catch {
                // A failed page is not a failed listing — what is already on screen
                // stays, and the footer stops asking for more.
                self.continuation = nil
                self.isLoading = false
            }
        }
    }
}
