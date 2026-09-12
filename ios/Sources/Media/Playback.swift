import AVFoundation
import Foundation

/// Playing a video without downloading it first.
///
/// A port of the Mac app's `Core/PreviewSession.swift`. The player-building half came
/// across unchanged — it was already AVFoundation — and only the resolving half was
/// rewritten, from a yt-dlp invocation to a `StreamResolver` call.
///
/// The preferred source is YouTube's HLS master playlist: one URL carrying every
/// rendition and the audio, which AVPlayer handles end to end, adaptively and seekably.
/// That matters more on a phone than it did on the Mac, because the connection changes
/// under you — HLS drops a rung on a bad cell and climbs back, where a fixed stream
/// stalls. Stitching two separate streams is the fallback, and it makes AVFoundation
/// index both remote files before the first frame, which is slow on a long video.
@MainActor
@Observable
final class Playback {
    enum State {
        case working(String)          // the stage, so a slow open is not a black box
        case ready(AVPlayer)
        case failed(String)
    }

    /// YouTube can sit there indefinitely, and the UI would sit on a spinner with it.
    private static let resolveTimeout: Duration = .seconds(45)

    private(set) var video: Video?
    private(set) var state: State = .working("Finding a stream…")
    /// Width / height, so the player is framed correctly — a Short is not the same
    /// shape as a talk.
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
                Self.activateAudioSession()
                let resolved = try await self.timed(Self.resolveTimeout, "finding a stream") {
                    try await StreamResolver.resolve(videoID: video.id, for: .playback)
                }
                try Task.checkCancellation()

                self.state = .working("Starting playback…")
                let built = try await Self.makePlayer(from: resolved)
                try Task.checkCancellation()

                self.aspectRatio = built.ratio
                self.state = .ready(built.player)
                built.player.play()
                self.watch(built.player)
                Log.preview.info("playing \(video.id, privacy: .public) "
                    + "via \(resolved.client, privacy: .public)")
            } catch is CancellationError {
                Log.preview.info("cancelled \(video.id, privacy: .public)")
            } catch {
                let message = Self.describe(error)
                Log.preview.error("failed \(video.id, privacy: .public): "
                    + "\(message, privacy: .public)")
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

    /// Let playback keep going with the screen locked, and stop it muting when the
    /// ringer switch is set to silent — this is a video the user deliberately started,
    /// not an autoplaying ad. Has to happen before the player is handed any item.
    private static func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Not fatal: playback still works, it just obeys the mute switch.
            Log.preview.error("audio session: \(error.localizedDescription, privacy: .public)")
        }
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

    // MARK: - Building the player

    private struct Built {
        let player: AVPlayer
        let ratio: CGFloat
    }

    private static func makePlayer(from resolved: StreamResolver.Resolved) async throws -> Built {
        switch resolved.source {
        case .hls(let url):
            // Hand the URL straight over. Deliberately no track pre-loading — that is
            // what hung on long videos, and the player shows its own buffering spinner.
            Log.preview.debug("hls player")
            return Built(player: AVPlayer(playerItem: AVPlayerItem(url: url)),
                         ratio: resolved.aspectRatio ?? 16.0 / 9.0)

        case .audioOnly(let audio):
            return Built(player: AVPlayer(playerItem: AVPlayerItem(url: audio.url)),
                         ratio: resolved.aspectRatio ?? 16.0 / 9.0)

        case .pair(let video, let audio):
            guard let audio else {
                let asset = AVURLAsset(url: video.url)
                let ratio = try await Self.ratio(of: asset) ?? resolved.aspectRatio
                return Built(player: AVPlayer(playerItem: AVPlayerItem(asset: asset)),
                             ratio: ratio ?? 16.0 / 9.0)
            }

            Log.preview.debug("stitching two streams")
            let videoAsset = AVURLAsset(url: video.url)
            let audioAsset = AVURLAsset(url: audio.url)

            let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            let span = try await videoAsset.load(.duration)

            guard let videoTrack = videoTracks.first, let audioTrack = audioTracks.first else {
                throw StreamResolver.Failure.noStreams
            }

            let composition = AVMutableComposition()
            guard let videoSlot = composition.addMutableTrack(
                    withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audioSlot = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw StreamResolver.Failure.noStreams }

            let range = CMTimeRange(start: .zero, duration: span)
            try videoSlot.insertTimeRange(range, of: videoTrack, at: .zero)
            videoSlot.preferredTransform = try await videoTrack.load(.preferredTransform)
            // The audio stream can be a hair shorter; a mismatch here would throw.
            try? audioSlot.insertTimeRange(range, of: audioTrack, at: .zero)

            let size = try await videoTrack.load(.naturalSize)
            let ratio = size.height > 0 ? size.width / size.height : 16.0 / 9.0
            return Built(player: AVPlayer(playerItem: AVPlayerItem(asset: composition)),
                         ratio: ratio)
        }
    }

    private static func ratio(of asset: AVURLAsset) async throws -> CGFloat? {
        guard let track = try await asset.loadTracks(withMediaType: .video).first
        else { return nil }
        let size = try await track.load(.naturalSize)
        return size.height > 0 ? size.width / size.height : nil
    }

    // MARK: - Helpers

    /// Run `work`, giving up after `limit`. Cancelling the inner task is what actually
    /// stops a stalled load — AVFoundation's async loads honour cancellation.
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
        case timedOut(String)
        var errorDescription: String? {
            switch self {
            case .timedOut(let what):
                "Gave up \(what) — YouTube did not respond in time."
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let known = error as? LocalizedError, let text = known.errorDescription {
            return text
        }
        let text = error.localizedDescription
        // AVFoundation's generic NSError says nothing useful on its own.
        if text.isEmpty || text.localizedCaseInsensitiveContains("could not be completed") {
            return "Could not start playback of this video. Downloading it may still work."
        }
        return text
    }
}
