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

    var canLoadMore: Bool { status == .paused }
    var isBusy: Bool { status == .running }

    // MARK: - Control

    func reset() {
        stop()
        videos = []
        seen = []
        channel = ""
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
        if status == .running { status = .stopped }
    }

    func start(rawURL: String, tab: ChannelTab) {
        stop()
        videos = []
        seen = []
        channel = ""
        error = nil
        outerCursor = 0
        exhausted = false
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
                    if !self.videos.isEmpty { break }
                }
                guard !self.videos.isEmpty else { throw YtDlp.Failure.noTab(tab.label) }
                self.settle()
            } catch is CancellationError {
                // stop() already recorded the state
            } catch {
                self.fail(error)
            }
        }
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
        status = exhausted ? .done : .paused
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
        while videos.count < target {
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
                if channel.isEmpty {
                    channel = (json["playlist_channel"] as? String)
                        ?? (json["playlist_title"] as? String) ?? ""
                }
                await absorb(json, depth: 0)

                if videos.count >= target {
                    chunk.reachedTarget = true
                    stream.terminate()      // page is full; stop walking the channel
                    break
                }
            }
        } catch let failure as ProcessStream.Failure {
            // A tab the channel does not have exits non-zero having printed nothing.
            // With entries already in hand that is just the end of the listing.
            if chunk.consumed == 0 && videos.isEmpty { throw failure }
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
                videos.append(video)
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
