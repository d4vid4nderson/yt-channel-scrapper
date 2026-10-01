import AVFoundation
import Foundation

/// Repeat: when a video reaches its end, start it again.
///
/// One setting for the whole app, not per player, because the same `AVPlayer` moves
/// between the player at the top, the Now Playing bar and the notch — a video set to
/// repeat in one should still repeat after it has been moved to another. So the watch is
/// attached to the player's item once, where the player is made (`PreviewSession`), and
/// reads this flag at the moment the item ends. Remembered between launches.
@MainActor
@Observable
final class PlaybackRepeat {
    static let shared = PlaybackRepeat()
    private static let key = "player.repeat"

    var isOn: Bool {
        didSet { UserDefaults.standard.set(isOn, forKey: Self.key) }
    }

    private init() {
        isOn = UserDefaults.standard.bool(forKey: Self.key)
    }

    /// Watch this player's current item for its end. The observer is tied to the item's
    /// lifetime — it goes when the item does — so nothing has to be detached when the
    /// player is closed or handed on.
    func attach(to player: AVPlayer) {
        guard let item = player.currentItem else { return }
        let observer = EndObserver(player: player)
        NotificationCenter.default.addObserver(
            observer, selector: #selector(EndObserver.ended(_:)),
            name: AVPlayerItem.didPlayToEndTimeNotification, object: item)
        objc_setAssociatedObject(item, &EndObserver.key, observer, .OBJC_ASSOCIATION_RETAIN)
    }
}

/// `@unchecked Sendable`: its one mutable thing, the weak player, is only ever read on
/// the main actor.
private final class EndObserver: NSObject, @unchecked Sendable {
    nonisolated(unsafe) static var key: UInt8 = 0
    weak var player: AVPlayer?

    init(player: AVPlayer) { self.player = player }

    /// Posted on whatever thread AVFoundation likes, so it hops to the main one.
    @objc func ended(_ note: Notification) {
        Task { @MainActor [weak self] in
            guard PlaybackRepeat.shared.isOn, let player = self?.player else { return }
            await player.seek(to: .zero)
            player.play()
        }
    }
}
