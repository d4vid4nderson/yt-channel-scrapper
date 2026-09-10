import AVFoundation
import Foundation

/// Plays a video in the app, without downloading it first.
///
/// YouTube no longer serves progressive (muxed) formats, so there is no single URL to
/// hand a player: video and audio arrive as separate streams. They are stitched into an
/// `AVMutableComposition`, which streams both over HTTP and keeps them in sync — so the
/// preview is a real native player rather than an embedded web view.
@MainActor
@Observable
final class PreviewSession {
    enum State {
        case working(String)          // the stage, so a slow open is not a black box
        case ready(AVPlayer)
        case failed(String)
    }

    /// yt-dlp can sit there indefinitely if YouTube stops answering, and the UI would
    /// sit on a spinner with it.
    private static let resolveTimeout: Duration = .seconds(45)

    private(set) var video: Video?
    private(set) var state: State = .working("Finding a stream…")
    /// Width / height of the stream, so the window frames it correctly — a Short is not
    /// the same shape as a talk.
    private(set) var aspectRatio: CGFloat = 16.0 / 9.0

    private var task: Task<Void, Never>?
    private var statusWatch: Task<Void, Never>?

    var isOpen: Bool { video != nil }

    func open(_ video: Video) {
        close()
        self.video = video
        state = .working("Finding a stream…")
        Log.preview.info("open \(video.id, privacy: .public)")

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let urls = try await self.timed(Self.resolveTimeout, "finding a stream") {
                    try await self.resolve(video)
                }
                try Task.checkCancellation()
                Log.preview.info("resolved, stitching: \(urls.audio != nil, privacy: .public)")

                self.state = .working("Starting playback…")
                let built = try await Self.makePlayer(from: urls)
                try Task.checkCancellation()

                self.aspectRatio = built.ratio
                self.state = .ready(built.player)
                built.player.play()
                self.watch(built.player)
                Log.preview.info("playing \(video.id, privacy: .public)")
            } catch is CancellationError {
                Log.preview.info("cancelled \(video.id, privacy: .public)")
            } catch {
                let message = Self.describe(error)
                Log.preview.error("failed \(video.id, privacy: .public): \(message, privacy: .public)")
                self.state = .failed(message)
            }
        }
    }

    func close() {
        task?.cancel()
        task = nil
        statusWatch?.cancel()
        statusWatch = nil
        if case .ready(let player) = state {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        state = .working("Finding a stream…")
        video = nil
    }

    /// Give up the player without tearing it down — it is moving to the island.
    func handOff() -> (player: AVPlayer, ratio: CGFloat, video: Video)? {
        guard case .ready(let player) = state, let video else { return nil }
        statusWatch?.cancel()
        statusWatch = nil
        task?.cancel()
        task = nil
        let ratio = aspectRatio
        state = .working("Finding a stream…")
        self.video = nil
        Log.preview.info("handed off \(video.id, privacy: .public)")
        return (player, ratio, video)
    }

    /// Take a still-playing player back from the island.
    func adopt(video: Video, player: AVPlayer, ratio: CGFloat) {
        close()
        self.video = video
        aspectRatio = ratio
        state = .ready(player)
        watch(player)
        Log.preview.info("adopted \(video.id, privacy: .public)")
    }

    /// An item can fail after the player is handed over — an expired URL, a codec the
    /// composition cannot handle. Without this the stage just sits there black.
    private func watch(_ player: AVPlayer) {
        statusWatch = Task { [weak self] in
            guard let item = player.currentItem else { return }
            while !Task.isCancelled {
                if item.status == .failed {
                    let message = item.error?.localizedDescription
                        ?? "The stream stopped working."
                    Log.preview.error("item failed: \(message, privacy: .public)")
                    self?.state = .failed(message)
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Resolving

    /// What the preview will play.
    private struct Resolved {
        /// The HLS master playlist, or the video stream when stitching.
        let primary: URL
        /// Only set when stitching separate streams, which YouTube rarely needs now.
        let audio: URL?
        let ratio: CGFloat?
    }

    /// Two passes over the short preview ladder: the HLS master first, since that is
    /// what works and what plays best, and only if no rung has one does it fall back to
    /// stitching separate streams. The common path is a single yt-dlp call.
    private func resolve(_ video: Video) async throws -> Resolved {
        var lastError: Error?

        for rung in YtDlp.previewLadder {
            if Task.isCancelled { throw CancellationError() }
            Log.preview.info("manifest attempt via \(rung.name, privacy: .public)")
            do {
                let lines = try await collect(YtDlp.manifestArguments(video: video, rung: rung))
                if let resolved = Self.parseManifest(lines) {
                    Log.preview.info("hls master via \(rung.name, privacy: .public)")
                    return resolved
                }
            } catch {
                lastError = error
            }
        }

        // No HLS anywhere: stitch the separate streams instead.
        for rung in YtDlp.previewLadder {
            if Task.isCancelled { throw CancellationError() }
            Log.preview.info("split attempt via \(rung.name, privacy: .public)")
            do {
                let urls = try await collect(YtDlp.streamArguments(video: video, rung: rung))
                    .compactMap { line -> URL? in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        return trimmed.hasPrefix("http") ? URL(string: trimmed) : nil
                    }
                if let first = urls.first {
                    Log.preview.info("split streams via \(rung.name, privacy: .public)")
                    return Resolved(primary: first,
                                    audio: urls.count > 1 ? urls[1] : nil,
                                    ratio: nil)
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? Failure.noStream
    }

    private static func parseManifest(_ lines: [String]) -> Resolved? {
        for line in lines {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard let head = parts.first?.trimmingCharacters(in: .whitespaces),
                  head.hasPrefix("http"), let url = URL(string: head)
            else { continue }
            var ratio: CGFloat?
            if parts.count >= 3,
               let width = Double(parts[1]), let height = Double(parts[2]), height > 0 {
                ratio = width / height
            }
            return Resolved(primary: url, audio: nil, ratio: ratio)
        }
        return nil
    }

    private func collect(_ arguments: [String]) async throws -> [String] {
        let stream = ProcessStream(
            executable: Paths.ytdlp,
            arguments: arguments,
            environment: YtDlp.environment
        )
        var lines: [String] = []
        for try await line in stream.lines() { lines.append(line) }
        return lines
    }

    // MARK: - Building the player

    private struct Built {
        let player: AVPlayer
        let ratio: CGFloat
    }

    private static func makePlayer(from resolved: Resolved) async throws -> Built {
        // HLS: hand the URL straight over. Deliberately no track pre-loading — that is
        // what hung on long videos, and AVPlayerView shows its own buffering spinner.
        guard let audio = resolved.audio else {
            let asset = AVURLAsset(url: resolved.primary)
            Log.preview.debug("hls player")
            return Built(player: AVPlayer(playerItem: AVPlayerItem(asset: asset)),
                         ratio: resolved.ratio ?? 16.0 / 9.0)
        }

        // Stitching fallback: two streams into one composition.
        let videoAsset = AVURLAsset(url: resolved.primary)
        let audioAsset = AVURLAsset(url: audio)
        Log.preview.debug("stitching two streams")

        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let span = try await videoAsset.load(.duration)

        guard let videoTrack = videoTracks.first, let audioTrack = audioTracks.first else {
            throw Failure.noStream
        }

        let composition = AVMutableComposition()
        guard let videoSlot = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioSlot = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure.noStream }

        let range = CMTimeRange(start: .zero, duration: span)
        try videoSlot.insertTimeRange(range, of: videoTrack, at: .zero)
        // The audio stream can be a hair shorter; a mismatch here would throw.
        try? audioSlot.insertTimeRange(range, of: audioTrack, at: .zero)

        let size = try await videoTrack.load(.naturalSize)
        let ratio = size.height > 0 ? size.width / size.height : 16.0 / 9.0
        return Built(player: AVPlayer(playerItem: AVPlayerItem(asset: composition)), ratio: ratio)
    }

    // MARK: - Helpers

    /// Run `work`, giving up after `limit`. Cancelling the inner task is what actually
    /// stops a stalled asset load — AVFoundation's async loads honour cancellation.
    private func timed<T: Sendable>(
        _ limit: Duration,
        _ what: String,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let worker = Task { try await work() }
        let watchdog = Task {
            try? await Task.sleep(for: limit)
            worker.cancel()
        }
        defer { watchdog.cancel() }
        do {
            return try await worker.value
        } catch is CancellationError {
            if Task.isCancelled { throw CancellationError() }   // we were closed
            throw Failure.timedOut(what)
        }
    }

    private enum Failure: LocalizedError {
        case noStream
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .noStream:
                "No playable stream came back for this video."
            case .timedOut(let what):
                "Gave up \(what) — YouTube did not respond in time."
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let known = error as? Failure { return known.errorDescription ?? "Preview failed." }
        if let failure = error as? ProcessStream.Failure {
            let lines = failure.message.split(separator: "\n")
            let line = lines.last(where: { $0.contains("ERROR") }) ?? lines.last ?? ""
            var text = line.replacingOccurrences(of: "ERROR: ", with: "")
            if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
                text = String(text[text.index(after: close)...])
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return String(trimmed.prefix(240)) }
        }
        let text = error.localizedDescription
        // AVFoundation's generic NSError says nothing useful on its own.
        if text.isEmpty || text.localizedCaseInsensitiveContains("could not be completed") {
            return "Could not start playback of this video. Downloading it should still work."
        }
        return text
    }
}
