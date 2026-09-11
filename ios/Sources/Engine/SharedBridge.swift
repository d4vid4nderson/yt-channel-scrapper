import Foundation

/// Small additions to the model types the iOS target shares with the Mac app.
///
/// These live here rather than in `mac/Sources/.../Model/` on purpose: the Mac app is
/// shipping, cannot be compiled from this side of the port, and gains nothing from any
/// of it. Extensions let the iOS target have what it needs without a single edit over
/// there — so a mistake here cannot break the Mac build.

extension Video {
    /// A video built from something other than yt-dlp's JSON.
    ///
    /// `Video` declares `init?(json:)`, and declaring any initialiser in a struct
    /// suppresses the memberwise one, so InnerTube's parser has no way in without this.
    init(
        id: String,
        title: String,
        duration: Int?,
        views: Int?,
        channelName: String?,
        channelId: String?
    ) {
        // Route through the JSON initialiser rather than restating the property
        // assignments: `Video`'s stored properties are `let`, so a second memberwise
        // initialiser would have to live in the type itself. Force-unwrapped because the
        // only failure `init?(json:)` has is a missing id, and `id` is non-optional here.
        var json: [String: Any] = ["id": id, "title": title]
        if let duration { json["duration"] = NSNumber(value: duration) }
        if let views { json["view_count"] = NSNumber(value: views) }
        if let channelName { json["channel"] = channelName }
        if let channelId { json["channel_id"] = channelId }
        self.init(json: json)!
    }
}

extension Quality {
    /// The Mac label says "Audio only (mp3)". iOS produces `.m4a` instead, and the
    /// difference is not cosmetic: the Mac transcodes with a vendored lame, which is a
    /// second decode-and-encode pass, whereas YouTube's audio stream is already AAC and
    /// AVFoundation can write it into an m4a untouched. Faster, and a better file.
    var iosLabel: String {
        self == .audio ? "Audio only (m4a)" : label
    }

    /// Tallest video stream this quality will accept, or nil for "whatever is best".
    var heightCap: Int? {
        switch self {
        case .best:  nil
        case .p1080: 1080
        case .p720:  720
        case .p480:  480
        case .audio: nil
        }
    }
}
