import AppIntents
import Foundation

/// The Now Playing widget's buttons.
///
/// `AudioPlaybackIntent` is what makes these work at all: iOS runs an intent of that kind
/// in the *app's* process — waking it in the background if it has to — rather than in
/// the widget's, and the player lives in the app. Compiled into both targets so the
/// widget can name them; only the app's copy ever runs, which is why the widget's copy
/// of `PlayerRemote` below is empty.
struct TogglePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await PlayerRemote.toggle()
        return .result()
    }
}

struct SkipPlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Skip"
    static let isDiscoverable = false

    @Parameter(title: "Seconds")
    var seconds: Double

    init() { seconds = 15 }
    init(seconds: Double) { self.seconds = seconds }

    func perform() async throws -> some IntentResult {
        await PlayerRemote.skip(by: seconds)
        return .result()
    }
}

/// Play a video from a widget, without opening the app. It plays as sound, the way a
/// video left playing behind the lock screen does, and the picture is there when the app
/// is opened. On a minor's phone it goes through the same approval check as any other
/// play, so a stale widget cannot play something since withdrawn.
struct PlayVideoIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Video"
    static let isDiscoverable = false

    @Parameter(title: "Video") var videoID: String
    @Parameter(title: "Title") var videoTitle: String
    @Parameter(title: "Channel") var channelID: String?
    @Parameter(title: "Channel Name") var channelName: String?

    init() {}
    init(videoID: String, title: String, channelID: String?, channelName: String?) {
        self.videoID = videoID
        self.videoTitle = title
        self.channelID = channelID
        self.channelName = channelName
    }

    func perform() async throws -> some IntentResult {
        await PlayerRemote.play(id: videoID, title: videoTitle,
                                channelID: channelID, channelName: channelName)
        return .result()
    }
}

/// The next video from the same channel.
struct NextVideoIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Video"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await PlayerRemote.next()
        return .result()
    }
}

struct CycleRepeatIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Repeat"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await PlayerRemote.cycleRepeat()
        return .result()
    }
}

/// Off, the one video, or the channel it came from and back to the start.
enum RepeatMode: String, Codable, Sendable, CaseIterable {
    case off, video, channel

    var next: RepeatMode {
        switch self {
        case .off: .video
        case .video: .channel
        case .channel: .off
        }
    }

    var symbol: String { self == .video ? "repeat.1" : "repeat" }

    var label: String {
        switch self {
        case .off: "Repeat Off"
        case .video: "Repeat Video"
        case .channel: "Repeat Channel"
        }
    }
}

#if WIDGET_EXTENSION
/// Never called: the system runs these intents in the app.
enum PlayerRemote {
    static func toggle() async {}
    static func skip(by seconds: Double) async {}
    static func cycleRepeat() async {}
    static func play(id: String, title: String, channelID: String?, channelName: String?) async {}
    static func next() async {}
}
#else
/// The app's end: the same transport the Lock Screen uses, then the widgets told at once
/// so the button they just pressed shows what it did.
@MainActor
enum PlayerRemote {
    static func toggle() {
        NowPlaying.shared.toggle()
        WidgetFeed.shared.refreshNow()
    }

    static func skip(by seconds: Double) {
        NowPlaying.shared.skip(by: seconds)
        WidgetFeed.shared.refreshNow()
    }

    static func cycleRepeat() {
        RepeatSetting.shared.mode = RepeatSetting.shared.mode.next
        WidgetFeed.shared.refreshNow()
    }

    static func play(id: String, title: String, channelID: String?, channelName: String?) async {
        let model = AppModel.shared
        // Woken cold for this, a minor's phone has not read its shelf yet, and with no
        // shelf nothing is approved — the right answer, but not the one wanted here.
        if model.isMinor && model.shelf.lastRead == nil { await model.syncShelf() }
        var json: [String: Any] = ["id": id, "title": title]
        if let channelID { json["channel_id"] = channelID }
        if let channelName { json["channel"] = channelName }
        let known = model.savedVideos.first { $0.id == id }
        guard let video = known ?? Video(json: json) else { return }
        model.startInBackground(video)
        WidgetFeed.shared.update(from: model)
    }

    static func next() {
        AppModel.shared.playNext()
    }
}
#endif
