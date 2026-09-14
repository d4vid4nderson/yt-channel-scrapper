import AVFoundation
import Foundation
import MediaPlayer
import UIKit

/// The Lock Screen, Control Centre, Dynamic Island, AirPods and CarPlay controls.
///
/// These are not separate features to build. iOS has exactly one "now playing" surface
/// and every one of those is a window onto it: fill in `MPNowPlayingInfoCenter`, register
/// handlers with `MPRemoteCommandCenter`, and the artwork, the scrubber and the transport
/// buttons appear in all of them at once.
///
/// Without this the app was already *able* to keep playing with the screen locked —
/// `UIBackgroundModes: audio` in the Info.plist and `Playback.activateAudioSession()`
/// arrange that much — but it came out as audio from nowhere, with no title, no artwork,
/// and no way to pause it short of unlocking the phone and finding the sheet again.
///
/// The info centre is told the elapsed time once per state change rather than
/// continuously. It extrapolates from the playback rate, so a scrubber told "12 seconds
/// in, playing at 1×" keeps itself correct. The refresh loop exists only to notice the
/// changes this class did not make — the player's own transport controls, an item
/// reaching its end, a duration that was not known yet when the player was handed over.
@MainActor
final class NowPlaying {
    static let shared = NowPlaying()

    private weak var player: AVPlayer?
    private var info: [String: Any] = [:]
    private var refresh: Task<Void, Never>?
    private var artwork: Task<Void, Never>?
    private var wired = false
    private var lastRate: Float = 0

    private init() {}

    // MARK: - Lifecycle

    /// Take the now playing surface over for `player`.
    func begin(player: AVPlayer, title: String, subtitle: String?, artwork url: URL?,
               isVideo: Bool) {
        wireCommands()
        self.player = player
        self.artwork?.cancel()

        info = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyMediaType:
                (isVideo ? MPNowPlayingInfoMediaType.video : .audio).rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if let subtitle, !subtitle.isEmpty { info[MPMediaItemPropertyArtist] = subtitle }

        setCommandsEnabled(true)
        sync()
        if let url { load(artwork: url) }

        refresh?.cancel()
        refresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let player = self.player else { return }
                // Only republish when something moved on its own. Rewriting the
                // dictionary every second would be churn the lock screen cannot show.
                if player.rate != self.lastRate || self.needsDuration(from: player) {
                    self.sync()
                }
            }
        }
    }

    /// Hand the surface back. Leaving a stale entry behind would keep this app listed as
    /// what is playing long after it stopped, and steal the controls from whatever the
    /// user started next.
    func end() {
        refresh?.cancel()
        refresh = nil
        artwork?.cancel()
        artwork = nil
        player = nil
        info = [:]
        lastRate = 0
        setCommandsEnabled(false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Publishing

    /// Push the current position and rate out to every control surface.
    private func sync() {
        guard let player else { return }
        lastRate = player.rate

        if let duration = player.currentItem?.duration.seconds,
           duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        let elapsed = player.currentTime().seconds
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed.isFinite ? elapsed : 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(player.rate)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// A streamed item reports `indefinite` until it has loaded enough to know better,
    /// so the duration has to be picked up after the fact rather than at `begin`.
    private func needsDuration(from player: AVPlayer) -> Bool {
        guard info[MPMediaItemPropertyPlaybackDuration] == nil else { return false }
        guard let duration = player.currentItem?.duration.seconds else { return false }
        return duration.isFinite && duration > 0
    }

    /// Fetch the poster and hand it over once it arrives.
    ///
    /// The request handler re-decodes from `Data` rather than closing over a `UIImage`,
    /// and is explicitly `@Sendable`. Both halves of that are load-bearing. MediaPlayer
    /// calls this handler from its own queue whenever something needs the artwork at a
    /// size it has not cached, so a closure written plainly inline here — inheriting
    /// this class's main-actor isolation, as every closure in a `@MainActor` type does —
    /// fails its isolation check the first time the lock screen asks, and the process is
    /// killed outright with no crash report to explain it. `@Sendable` opts the closure
    /// out of that isolation, which is only sound because the capture is plain bytes.
    private func load(artwork url: URL) {
        artwork = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let decoded = UIImage(data: data), !Task.isCancelled, let self
            else { return }
            let draw: @Sendable (CGSize) -> UIImage = { _ in UIImage(data: data) ?? UIImage() }
            self.info[MPMediaItemPropertyArtwork] =
                MPMediaItemArtwork(boundsSize: decoded.size, requestHandler: draw)
            self.sync()
        }
    }

    // MARK: - Remote commands

    /// What `addTarget` is handed.
    ///
    /// Spelled out, and `@Sendable`, for the same reason the artwork handler is: these
    /// are called from MediaPlayer's queues, and a closure that inherited this class's
    /// main-actor isolation would trap on the first press of a lock screen button. Each
    /// one therefore pulls the value it needs out of the event synchronously — the event
    /// object itself cannot cross onto the main actor — and hops over to do the work.
    private typealias Handler = @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus

    /// Registered once for the life of the process and enabled or disabled around each
    /// item. Adding targets per playback would stack them up, and every handler would
    /// fire on every button press.
    private func wireCommands() {
        guard !wired else { return }
        wired = true
        let center = MPRemoteCommandCenter.shared()

        let play: Handler = { _ in
            Task { @MainActor in NowPlaying.shared.setRate(1) }
            return .success
        }
        let pause: Handler = { _ in
            Task { @MainActor in NowPlaying.shared.setRate(0) }
            return .success
        }
        let toggle: Handler = { _ in
            Task { @MainActor in NowPlaying.shared.toggle() }
            return .success
        }
        let forward: Handler = { event in
            let by = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in NowPlaying.shared.skip(by: by) }
            return .success
        }
        let backward: Handler = { event in
            let by = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in NowPlaying.shared.skip(by: -by) }
            return .success
        }
        let scrub: Handler = { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            let to = event.positionTime
            Task { @MainActor in NowPlaying.shared.seek(to: to) }
            return .success
        }

        center.playCommand.addTarget(handler: play)
        center.pauseCommand.addTarget(handler: pause)
        center.togglePlayPauseCommand.addTarget(handler: toggle)
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget(handler: forward)
        center.skipBackwardCommand.addTarget(handler: backward)
        center.changePlaybackPositionCommand.addTarget(handler: scrub)

        // There is no queue behind this — one sheet, one video. Left enabled they would
        // draw next/previous buttons that do nothing.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    private func setCommandsEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                        center.skipForwardCommand, center.skipBackwardCommand,
                        center.changePlaybackPositionCommand] {
            command.isEnabled = enabled
        }
    }

    // MARK: - Acting on them

    private func setRate(_ rate: Float) {
        player?.rate = rate
        sync()
    }

    private func toggle() {
        guard let player else { return }
        setRate(player.rate > 0 ? 0 : 1)
    }

    private func skip(by seconds: TimeInterval) {
        guard let player else { return }
        let now = player.currentTime().seconds
        guard now.isFinite else { return }
        seek(to: max(0, now + seconds))
    }

    private func seek(to seconds: TimeInterval) {
        guard let player else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        sync()
    }
}
