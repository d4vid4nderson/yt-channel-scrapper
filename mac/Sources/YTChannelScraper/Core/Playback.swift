import AVFoundation
import Foundation

/// Playback state for a running `AVPlayer`, in a form SwiftUI can bind to.
///
/// `AVPlayer` reports position through a periodic observer rather than KVO-friendly
/// properties, so the mini player would otherwise have nothing to drive a scrubber with.
@MainActor
@Observable
final class Playback {
    private(set) var isPlaying = false
    private(set) var current: Double = 0
    private(set) var duration: Double = 0
    /// Live streams have no meaningful end, so the scrubber becomes a LIVE badge.
    private(set) var isLive = false

    var volume: Float {
        didSet { player?.volume = volume }
    }

    private weak var player: AVPlayer?
    private var ticker: Any?
    private var rateWatch: NSKeyValueObservation?

    init() {
        volume = 1
    }

    func attach(_ player: AVPlayer) {
        detach()
        self.player = player
        volume = player.volume

        ticker = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.current = time.seconds.isFinite ? time.seconds : 0
                let total = player.currentItem?.duration.seconds ?? .nan
                if total.isFinite, total > 0 {
                    self.duration = total
                    self.isLive = false
                } else {
                    self.isLive = true
                }
            }
        }

        // KVO can deliver on any thread, so this one hops rather than assuming.
        rateWatch = player.observe(\.rate, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.rate != 0
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    func detach() {
        if let ticker, let player { player.removeTimeObserver(ticker) }
        ticker = nil
        rateWatch = nil
        player = nil
        isPlaying = false
        current = 0
        duration = 0
        isLive = false
    }

    func toggle() {
        guard let player else { return }
        player.rate == 0 ? player.play() : player.pause()
    }

    func seek(to seconds: Double) {
        guard let player, duration > 0 else { return }
        player.seek(
            to: CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func skip(_ delta: Double) { seek(to: current + delta) }

    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
