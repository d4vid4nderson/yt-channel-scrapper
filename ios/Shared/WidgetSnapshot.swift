import Foundation

/// What the Home Screen widget shows, written by the app and read by the widget.
///
/// Compiled into both targets. The widget is a separate process that cannot see the
/// library, the shelf or the player, and must not try: it would need the whole store
/// layer to do it, and on a minor's phone it would have to repeat the approval rules to
/// stay safe. So the app — which already applies those rules — decides what is on the
/// widget and writes it here, pictures included, into the App Group they share. The
/// widget only ever draws what it is handed.
struct WidgetSnapshot: Codable, Sendable {
    struct Item: Codable, Sendable, Hashable, Identifiable {
        var id: String
        var title: String
        var subtitle: String?
        /// A file name in `WidgetSnapshot.images`, when the picture has been fetched.
        var image: String?
        /// Where tapping it goes.
        var link: URL
    }

    /// What is in the player, or what was last in it.
    var nowPlaying: Item?
    /// True while the player holds it, false when it is only the last thing watched.
    var isPlaying: Bool
    /// Where the player was when this was written, while it holds something.
    var progress: Progress?
    var repeatMode: RepeatMode
    var videos: [Item]
    var channels: [Item]
    /// The Browse widget's shelves: each channel with the videos it can offer, which
    /// on a minor's phone are only the approved ones.
    var shelves: [Shelf]
    /// The channel of what is playing, with more from it — "More from" on the large Now
    /// Playing widget. Also first in `shelves`.
    var playingShelf: Shelf?

    struct Shelf: Codable, Sendable, Identifiable {
        var channel: Item
        var videos: [ShelfVideo]
        var id: String { channel.id }
    }

    /// A video the widget can play by itself, so it carries what `PlayVideoIntent` needs.
    struct ShelfVideo: Codable, Sendable, Identifiable {
        var item: Item
        var channelID: String?
        var channelName: String?
        var id: String { item.id }
    }
    /// False on a minor's phone, which has no Search tab to open.
    var allowsSearch: Bool

    /// Enough for the widget to keep a progress bar moving on its own: WidgetKit draws a
    /// `ProgressView(timerInterval:)` live, so a start and an end are all it needs while
    /// playing, and the widget is only rewritten when that changes — pause, seek, a new
    /// item.
    struct Progress: Codable, Sendable {
        var elapsed: Double
        var duration: Double?
        var isPaused: Bool
        var asOf: Date

        /// The span the video would cover, playing on from `asOf` at 1×.
        var interval: ClosedRange<Date>? {
            guard let duration, !isPaused else { return nil }
            let start = asOf.addingTimeInterval(-elapsed)
            return start...start.addingTimeInterval(duration)
        }

        var fraction: Double {
            guard let duration, duration > 0 else { return 0 }
            return min(max(elapsed / duration, 0), 1)
        }
    }

    struct RGB: Codable, Sendable {
        var r: Double, g: Double, b: Double
    }

    /// The active theme, flattened to what a widget can draw: the widget cannot compile
    /// Theme.swift (it is the app's whole look, UIKit and all), so the app resolves it
    /// and writes the answers down. Rewritten on every theme change.
    struct Look: Codable, Sendable {
        var accent: RGB
        var accent2: RGB
        var ground: RGB
        var surface: RGB
        var card: RGB
        var ink: RGB
        var onFill: RGB
        /// `Font.Design`, by name: default, serif, rounded, monospaced.
        var design: String
        /// `Font.Width`, by name: standard, condensed, compressed, expanded.
        var width: String
        /// The theme's heading face, when it has one. The widget falls back to the system
        /// font if this phone does not have it.
        var displayFont: String?
        var displayCaps: Bool
        /// rounded, chamfered or square, at the theme's scale.
        var corners: String
        var cornerScale: Double
        var isLight: Bool
    }

    var look: Look
    /// Every theme's look, by name, in the app's order — what a widget's own Theme option
    /// (Edit Widget) chooses from. `look` is the app's current one.
    var themes: [NamedLook]

    struct NamedLook: Codable, Sendable {
        /// `Theme.ID`'s raw value — what the widget's `WidgetTheme` matches on.
        var id: String
        var name: String
        var look: Look
    }

    static let empty = WidgetSnapshot(
        nowPlaying: nil, isPlaying: false, progress: nil, repeatMode: .off,
        videos: [], channels: [], shelves: [], playingShelf: nil, allowsSearch: false,
        look: Look(accent: RGB(r: 1, g: 0.2, b: 0.2), accent2: RGB(r: 1, g: 0.4, b: 0.4),
                   ground: RGB(r: 0.07, g: 0.07, b: 0.08), surface: RGB(r: 0.1, g: 0.1, b: 0.11),
                   card: RGB(r: 0.13, g: 0.13, b: 0.14), ink: RGB(r: 1, g: 1, b: 1),
                   onFill: RGB(r: 1, g: 1, b: 1), design: "default", width: "standard",
                   displayFont: nil, displayCaps: false, corners: "rounded", cornerScale: 1,
                   isLight: false),
        themes: []
    )

    // MARK: - Where it lives

    /// The App Group, from the Info.plist of whichever target is asking — both carry it,
    /// set from `YTCS_APP_GROUP` in project.yml so a changed bundle id carries it along.
    static var container: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "YTCSAppGroup") as? String
        else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    private static var file: URL? { container?.appendingPathComponent("widget.json") }

    static var images: URL? { container?.appendingPathComponent("WidgetImages", isDirectory: true) }

    static func imageURL(_ name: String) -> URL? { images?.appendingPathComponent(name) }

    static func load() -> WidgetSnapshot {
        guard let file, let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    func save() throws {
        guard let file = Self.file else { return }
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }
}

/// The links a widget opens the app with: `ytplayer://…`.
///
/// Registered as a URL scheme, which means anything on the phone can open one, not only
/// the widget. That is fine because none of them grants anything: a video still goes
/// through `AppModel.play`, which refuses what is not approved on a minor's phone, and
/// search is ignored there outright.
enum WidgetLink: Equatable, Sendable {
    case open
    case search
    case resume
    case airplay
    case video(id: String, title: String, channelID: String?, channelName: String?)
    case channel(id: String)

    static let scheme = "ytplayer"

    var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .open:   parts.host = "open"
        case .search: parts.host = "search"
        case .resume: parts.host = "resume"
        case .airplay: parts.host = "airplay"
        case .video(let id, let title, let channelID, let channelName):
            parts.host = "video"
            parts.path = "/\(id)"
            parts.queryItems = [URLQueryItem(name: "title", value: title)]
                + (channelID.map { [URLQueryItem(name: "channel", value: $0)] } ?? [])
                + (channelName.map { [URLQueryItem(name: "channelName", value: $0)] } ?? [])
        case .channel(let id):
            parts.host = "channel"
            parts.path = "/\(id)"
        }
        return parts.url!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let id = String(parts.path.dropFirst())
        func query(_ name: String) -> String? {
            parts.queryItems?.first { $0.name == name }?.value
        }
        switch parts.host {
        case "open":   self = .open
        case "search": self = .search
        case "resume": self = .resume
        case "airplay": self = .airplay
        case "video" where !id.isEmpty:
            self = .video(id: id, title: query("title") ?? id,
                          channelID: query("channel"), channelName: query("channelName"))
        case "channel" where !id.isEmpty:
            self = .channel(id: id)
        default: return nil
        }
    }
}
