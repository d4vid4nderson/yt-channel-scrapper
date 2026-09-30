import Foundation

/// Whether the player loops, and what it loops. Per phone, and kept across launches:
/// someone who set a channel of lullabies to repeat wants it still repeating tomorrow.
@Observable
@MainActor
final class RepeatSetting {
    static let shared = RepeatSetting()

    private static let key = "player.repeat.v1"

    var mode: RepeatMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) }
    }

    private init() {
        mode = UserDefaults.standard.string(forKey: Self.key).flatMap(RepeatMode.init) ?? .off
    }
}

extension AppModel {
    /// A video reached its end. With repeat off, nothing happens and the player stops
    /// where it is, as it always did.
    func finished(_ item: Playable) {
        switch RepeatSetting.shared.mode {
        case .off:
            return
        case .video:
            restart()
        case .channel:
            let queue = channelQueue(for: item)
            let currentID = item.video?.id ?? item.file?.videoID
            guard queue.count > 1 else { return restart() }
            let index = queue.firstIndex { $0.id == currentID }
            let next = queue[index.map { ($0 + 1) % queue.count } ?? 0]
            startInBackground(next)
        }
    }

    /// The next video along, repeat or not — what the Next control asks for.
    func playNext() {
        guard let item = playback.item else { return }
        let queue = channelQueue(for: item)
        let currentID = item.video?.id ?? item.file?.videoID
        guard queue.count > 1 else { return }
        let index = queue.firstIndex { $0.id == currentID }
        startInBackground(queue[index.map { ($0 + 1) % queue.count } ?? 0])
    }

    private func restart() {
        NowPlaying.shared.seek(to: 0)
        playback.current?.player.play()
    }

    /// What "the channel" means for the item that just ended: the videos you could have
    /// picked it from.
    ///
    /// On a minor's phone that is only ever the approved ones — never the channel's live
    /// listing, for the same reason `approvedVideos(of:)` gives: a channel repeating into
    /// everything it has posted would be the Search tab by another route. A parent gets
    /// the listing they were browsing when it is that channel, else the ones they saved.
    private func channelQueue(for item: Playable) -> [Video] {
        let currentID = item.video?.id ?? item.file?.videoID
        let channelID = item.video?.channelId
            ?? savedVideos.first { $0.id == currentID }?.channelId
        guard let channelID else { return savedVideos }
        if isMinor {
            return approvedVideos.filter { $0.channelId == channelID }
        }
        if listing.channel?.id == channelID, !listing.videos.isEmpty {
            return listing.videos
        }
        return library.videos.filter { $0.channelId == channelID }
    }

    /// Play the next video without putting the sheet up if it is not already: a channel
    /// on repeat behind the lock screen should stay there.
    func startInBackground(_ video: Video) {
        let next: Playable
        if isMinor, let file = localFile(for: video) {
            next = .local(file)
        } else if !isMinor || approvedIDs.contains(video.id) {
            next = .stream(video)
        } else {
            return
        }
        playback.open(next)
        // The sheet follows along if it is open; its `resume` finds the item already
        // opening and leaves it alone.
        if playing != nil { playing = next }
    }
}
