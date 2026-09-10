import Foundation

/// One row in the scraped list. Mirrors `_as_video` in the Flask app.
struct Video: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let duration: Int?
    let views: Int?

    var url: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    var thumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")! }

    /// yt-dlp emits one of these per line under `--dump-json --flat-playlist`. Entries
    /// without an id are playlist scaffolding rather than videos, so they drop out here.
    init?(json: [String: Any]) {
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

    var viewsText: String {
        guard let views else { return "" }
        switch views {
        case 1_000_000...:
            return "\(trim(Double(views) / 1_000_000))M views"
        case 1_000...:
            return "\(trim(Double(views) / 1_000))K views"
        default:
            return views == 1 ? "1 view" : "\(views) views"
        }
    }

    private func trim(_ value: Double) -> String {
        value < 10
            ? String(format: "%.1f", value).replacingOccurrences(of: ".0", with: "")
            : String(Int(value.rounded()))
    }
}
