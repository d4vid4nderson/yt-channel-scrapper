import Foundation

/// Which tab of a channel to list, and the path(s) that hold it.
///
/// Music is the awkward one: it lives under /releases on artist channels but under
/// /playlists on many others, so both are tried in order — same as `TABS` in app.py.
enum ChannelTab: String, CaseIterable, Identifiable, Sendable {
    case videos, shorts, live, music

    var id: String { rawValue }

    var label: String {
        switch self {
        case .videos: "Videos"
        case .shorts: "Shorts"
        case .live:   "Live"
        case .music:  "Music"
        }
    }

    var paths: [String] {
        switch self {
        case .videos: ["videos"]
        case .shorts: ["shorts"]
        case .live:   ["streams"]
        case .music:  ["releases", "playlists"]
        }
    }
}

enum Quality: String, CaseIterable, Identifiable, Sendable {
    case best, p1080 = "1080", p720 = "720", p480 = "480", audio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .best:  "Best available"
        case .p1080: "1080p"
        case .p720:  "720p"
        case .p480:  "480p"
        case .audio: "Audio only (mp3)"
        }
    }

    /// The order the picker offers, with the safe default first.
    static var menuOrder: [Quality] { [.p1080, .best, .p720, .p480, .audio] }

    var isAudioOnly: Bool { self == .audio }

    var formatSelector: String {
        switch self {
        case .best:  "bestvideo[height<=?2160]+bestaudio/best"
        case .p1080: "bestvideo[height<=?1080]+bestaudio/best[height<=?1080]"
        case .p720:  "bestvideo[height<=?720]+bestaudio/best[height<=?720]"
        case .p480:  "bestvideo[height<=?480]+bestaudio/best[height<=?480]"
        case .audio: "bestaudio/best"
        }
    }
}
