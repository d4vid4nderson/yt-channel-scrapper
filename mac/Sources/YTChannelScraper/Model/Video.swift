import Foundation

/// One row in the scraped list. Mirrors `_as_video` in the Flask app.
///
/// Codable because a saved video outlives the scrape it came from: it has to survive
/// a relaunch with enough on it to be listed and downloaded without re-reading the
/// channel.
struct Video: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let duration: Int?
    let views: Int?
    /// Whose channel it was. A scrape does not need this — the whole list is one
    /// channel, named in the header — but a saved list mixes channels, and then it is
    /// the only way to tell them apart.
    var channelName: String?
    /// The UC… id of that channel. More reliable than the name for deciding whether a
    /// kept video belongs to the channel on screen — names collide and get changed.
    var channelId: String?

    var url: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    var thumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")! }

    /// yt-dlp emits one of these per line under `--dump-json --flat-playlist`. Entries
    /// without an id are playlist scaffolding rather than videos, so they drop out here.
    init?(json: [String: Any]) {
        self.channelName = (json["playlist_channel"] as? String)
            ?? (json["channel"] as? String)
        self.channelId = (json["playlist_channel_id"] as? String)
            ?? (json["channel_id"] as? String)
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }
        self.id = id
        self.title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        self.duration = (json["duration"] as? NSNumber)?.intValue
        self.views = (json["view_count"] as? NSNumber)?.intValue
    }

    var durationText: String {
        guard let duration, duration > 0 else { return "" }
        let (h, m, s) = (duration / 3600, (duration % 3600) / 60, duration % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// What the row prints under the title.
    func metaText(showingChannel: Bool) -> String {
        var parts: [String] = []
        if showingChannel, let channelName, !channelName.isEmpty { parts.append(channelName) }
        if !viewsText.isEmpty { parts.append(viewsText) }
        return parts.joined(separator: "  ·  ")
    }

    var viewsText: String {
        guard let views else { return "" }
        if views < 1_000 { return views == 1 ? "1 view" : "\(views) views" }
        return "\(compactCount(views)) views"
    }
}
