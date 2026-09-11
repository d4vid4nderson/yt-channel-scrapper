import Foundation

/// One YouTube channel: a search hit, a saved favourite, or the channel a scrape came
/// from. One shape serves all three, so starring a search result is a copy rather than
/// a conversion.
struct Channel: Identifiable, Hashable, Codable, Sendable {
    /// The UC… id. It survives renames and handle changes, so it is what the library
    /// keys on — and it is the one column Takeout guarantees.
    let id: String
    var title: String
    /// "@fireship", when YouTube gave one.
    var handle: String?
    var subscribers: Int?
    var avatar: URL?

    init(id: String, title: String, handle: String? = nil, subscribers: Int? = nil, avatar: URL? = nil) {
        self.id = id
        self.title = title
        self.handle = handle
        self.subscribers = subscribers
        self.avatar = avatar
        self.savedAt = Date()
    }

    /// Prefer the handle: it is what people recognise and it reads properly in the URL
    /// field. The id form always resolves, so it is the fallback.
    var url: String {
        if let handle, handle.hasPrefix("@") {
            return "https://www.youtube.com/\(handle)"
        }
        return "https://www.youtube.com/channel/\(id)"
    }

    /// When it was starred, and when it was last opened. Both optional so a
    /// channels.json written before they existed still decodes.
    var savedAt: Date?
    var lastOpenedAt: Date?

    /// The tile has room for one fact, not two. Subscribers is the one worth keeping —
    /// the handle is already most of the way to being the name above it.
    var shelfSubtitle: String {
        if let subscribers, subscribers > 0 { return "\(compactCount(subscribers)) subscribers" }
        return handle ?? ""
    }

    var subtitle: String {
        var parts: [String] = []
        if let handle, !handle.isEmpty { parts.append(handle) }
        if let subscribers, subscribers > 0 {
            parts.append("\(compactCount(subscribers)) subscriber\(subscribers == 1 ? "" : "s")")
        }
        return parts.joined(separator: "  ·  ")
    }

    /// Drawn in place of a picture. A channel saved from a scrape has no avatar — a
    /// channel listing does not carry one — and Takeout's CSV has no picture either.
    var monogram: String {
        let words = title.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    /// A colour for that monogram, held steady across launches.
    ///
    /// `hashValue` is seeded per process and so would repaint every channel on every
    /// launch; summing the id's scalars does not.
    var hue: Double {
        let sum = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }
        return Double(sum) / 360
    }
}

// MARK: - Reading yt-dlp

extension Channel {
    /// One entry from the channel-filtered search listing.
    init?(searchJSON json: [String: Any]) {
        guard let id = (json["channel_id"] as? String) ?? (json["id"] as? String),
              id.hasPrefix("UC")
        else { return nil }

        let title = (json["channel"] as? String)
            ?? (json["title"] as? String)
            ?? id
        self.init(
            id: id,
            title: title,
            handle: json["uploader_id"] as? String,
            subscribers: (json["channel_follower_count"] as? NSNumber)?.intValue,
            avatar: Self.bestAvatar(json["thumbnails"])
        )
    }

    /// The channel a scraped listing belongs to. Every entry carries it, since the
    /// listing is the channel's own tab — but under `playlist_*`, because from yt-dlp's
    /// side the tab is the playlist and the video is the entry.
    init?(listingJSON json: [String: Any]) {
        guard let id = json["playlist_channel_id"] as? String, !id.isEmpty else { return nil }
        let title = (json["playlist_channel"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (json["playlist_title"] as? String)
            ?? id
        self.init(id: id, title: title, handle: json["playlist_uploader_id"] as? String)
    }

    /// Pick the channel's picture out of a thumbnail list.
    ///
    /// "Largest wins" is wrong here: a channel's own listing includes the banner, and
    /// the banner is the biggest entry in it by a wide margin. An avatar is square and
    /// a banner is a letterbox, so shape decides, and YouTube's own `avatar_*` label is
    /// the fallback for the entries that carry no dimensions.
    static func bestAvatar(_ raw: Any?) -> URL? {
        guard let thumbnails = raw as? [[String: Any]] else { return nil }

        func size(_ thumbnail: [String: Any], _ key: String) -> Int? {
            (thumbnail[key] as? NSNumber)?.intValue
        }

        let squares = thumbnails.filter {
            guard let width = size($0, "width"), let height = size($0, "height"),
                  width > 0, height > 0
            else { return false }
            return abs(width - height) <= max(width, height) / 10
        }
        let chosen = squares.max { (size($0, "width") ?? 0) < (size($1, "width") ?? 0) }
            ?? thumbnails.first { ($0["id"] as? String)?.contains("avatar") == true }

        guard var string = chosen?["url"] as? String, !string.isEmpty else { return nil }
        // Search results give these protocol-relative — "//yt3.ggpht.com/…" — which URL
        // parses happily and AsyncImage then fails to load, so the scheme goes back on.
        if string.hasPrefix("//") { string = "https:" + string }
        return URL(string: string)
    }
}


extension Channel {
    /// What a channel's own page says about it — the avatar above all, since that is
    /// the one thing neither a listing nor a Takeout row carries.
    struct Details: Sendable {
        var avatar: URL?
        var subscribers: Int?
        var handle: String?
        var title: String?
    }

    static func details(fromJSON json: [String: Any]) -> Details {
        Details(
            avatar: bestAvatar(json["thumbnails"]),
            subscribers: (json["channel_follower_count"] as? NSNumber)?.intValue,
            handle: json["uploader_id"] as? String,
            title: (json["channel"] as? String) ?? (json["title"] as? String)
        )
    }

    /// Fold in what was learned, leaving anything already known alone.
    mutating func apply(_ details: Details) {
        avatar = details.avatar ?? avatar
        subscribers = details.subscribers ?? subscribers
        handle = details.handle ?? handle
        if let title = details.title, !title.isEmpty { self.title = title }
    }

    var needsDetails: Bool { avatar == nil }
}