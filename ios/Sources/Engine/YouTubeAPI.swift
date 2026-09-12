import Foundation

/// The listing half of the engine: everything the app did through
/// `yt-dlp --flat-playlist --dump-json`, done with InnerTube calls instead.
///
/// Stateless on purpose — the paging and cancellation live in the `@Observable` types
/// that drive the UI, the same split the Mac app has between `YtDlp` (builds the call)
/// and `Scraper` (runs it and holds the result).
enum YouTubeAPI {

    /// One page of a channel tab.
    struct Page: Sendable {
        var videos: [Video]
        /// Feed to `continueListing` for the next page; nil when the tab is exhausted.
        var continuation: String?
        /// Only present on the first page — a continuation response carries no header.
        var channel: Channel?
    }

    // MARK: - Tabs

    /// The `params` blob that selects a tab, base64 protobuf YouTube's own web client
    /// sends. Opaque, stable for years, and the only way to browse straight to a tab
    /// without first fetching the channel page and reading its tab bar.
    ///
    /// Music is two params rather than one for the same reason it is two paths in
    /// `ChannelTab.paths`: artist channels put it under Releases and everyone else under
    /// Playlists, and which one a channel has is not knowable in advance.
    static func params(for tab: ChannelTab) -> [String] {
        switch tab {
        case .videos: ["EgZ2aWRlb3PyBgQKAjoA"]
        case .shorts: ["EgZzaG9ydHPyBgUKA5oBAA=="]
        case .live:   ["EgdzdHJlYW1z8gYECgJ6AA=="]
        case .music:  ["EghyZWxlYXNlc/IGBQoDsgEA", "EglwbGF5bGlzdHPyBgQKAkIA"]
        }
    }

    // MARK: - Resolving a channel

    /// Turn whatever the user typed into a `UC…` browse id.
    ///
    /// Accepts the same spread the Mac app does — a bare handle, a /@handle URL, a
    /// /channel/UC… URL, a /c/ or /user/ vanity URL — because that is what people paste.
    /// A `UC…` is returned as-is without a round trip; everything else is handed to
    /// YouTube's own resolver, which is the only thing that knows what a vanity URL
    /// points at.
    static func resolveChannel(from raw: String) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.noInput }

        // A bare id, or one sitting in a /channel/ URL, needs nobody's help.
        if trimmed.hasPrefix("UC"), trimmed.count == 24 { return trimmed }
        if let range = trimmed.range(of: "/channel/") {
            let tail = trimmed[range.upperBound...]
            let id = String(tail.prefix(while: { $0 != "/" && $0 != "?" }))
            if id.hasPrefix("UC") { return id }
        }

        var url = trimmed
        if !url.hasPrefix("http") {
            url = "https://www.youtube.com/" + url.drop(while: { $0 == "/" })
        }
        // Strip any tab suffix: the resolver wants the channel, not /videos.
        url = url.replacing(
            /\/(videos|shorts|streams|releases|playlists|podcasts|featured)\/?$/,
            with: ""
        )

        let response = try await InnerTube.post(
            "navigation/resolve_url",
            client: InnerTube.webClient,
            payload: ["url": url]
        )
        // A resolve response can carry more than one `browseId` — the channel's own and
        // a feed's — so the candidates are filtered rather than taking whichever the
        // tree walk reaches first, which is not a defined order.
        guard let id = Renderers.findAllValues("browseId", in: response, as: String.self)
            .first(where: { $0.hasPrefix("UC") && $0.count == 24 })
        else { throw Failure.notAChannel(trimmed) }
        return id
    }

    // MARK: - Listing

    /// The first page of a channel tab.
    ///
    /// Music tries its two params in order and keeps the first that returns anything,
    /// matching `ChannelTab.paths`. The others have exactly one, so the loop runs once.
    static func listChannelTab(browseID: String, tab: ChannelTab) async throws -> Page {
        var lastResponse: [String: Any]?

        for param in params(for: tab) {
            let response = try await InnerTube.post(
                "browse",
                client: InnerTube.webClient,
                payload: ["browseId": browseID, "params": param]
            )
            lastResponse = response

            var channel = Channel(id: browseID, title: browseID)
            channel.apply(Renderers.details(in: response))

            let videos = Renderers.videos(in: response, channel: channel)
            if !videos.isEmpty {
                return Page(videos: videos,
                            continuation: Renderers.continuation(in: response),
                            channel: channel)
            }
        }

        // Nothing on any param. Distinguish "this tab is empty" from "this channel does
        // not exist", because the first is worth saying precisely and the second is not
        // the user's fault for picking the wrong tab.
        if let lastResponse {
            var channel = Channel(id: browseID, title: browseID)
            channel.apply(Renderers.details(in: lastResponse))
            if channel.title != browseID {
                throw Failure.emptyTab(tab.label)
            }
        }
        throw Failure.notAChannel(browseID)
    }

    /// The next page. Continuations carry no header, so `Page.channel` is nil — the
    /// caller already has it from the first page.
    static func continueListing(token: String, channel: Channel?) async throws -> Page {
        let response = try await InnerTube.post(
            "browse",
            client: InnerTube.webClient,
            payload: ["continuation": token]
        )
        return Page(
            videos: Renderers.videos(in: response, channel: channel),
            continuation: Renderers.continuation(in: response),
            channel: nil
        )
    }

    // MARK: - Searching

    /// Search YouTube for channels rather than videos.
    ///
    /// `EgIQAg==` is the results page's own Channels filter, decoded from the
    /// `sp=EgIQAg%3D%3D` the Mac app puts in its search URL — same filter, passed as a
    /// parameter instead of smuggled through a URL.
    static let channelSearchParams = "EgIQAg=="

    static func searchChannels(query: String) async throws -> [Channel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response = try await InnerTube.post(
            "search",
            client: InnerTube.webClient,
            payload: ["query": trimmed, "params": channelSearchParams]
        )
        return Renderers.channels(in: response)
    }

    /// Fill in a channel's avatar and subscriber count. Used for channels that arrived
    /// from a listing or a Takeout import, which carry neither.
    static func details(for browseID: String) async throws -> Channel.Details {
        let response = try await InnerTube.post(
            "browse",
            client: InnerTube.webClient,
            payload: ["browseId": browseID]
        )
        return Renderers.details(in: response)
    }

    // MARK: - Failures

    enum Failure: LocalizedError {
        case noInput
        case notAChannel(String)
        case emptyTab(String)

        var errorDescription: String? {
            switch self {
            case .noInput:
                "Type a channel name or paste a URL."
            case .notAChannel(let what):
                "Could not find a channel for \"\(what)\"."
            case .emptyTab(let label):
                "No \(label) found for that channel — it may not have a \(label) tab. "
                    + "Try a different type."
            }
        }
    }
}
