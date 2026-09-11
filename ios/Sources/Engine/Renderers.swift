import Foundation

/// Reading InnerTube's responses.
///
/// Every shape below was checked against live responses rather than inferred — see
/// `ios/Tools/check-renderers.py`, which runs the same logic against YouTube right now
/// and is the thing to run when a listing comes back empty.
///
/// Two properties of those responses drive the whole design:
///
/// 1. **The wrappers move, the leaves stay.** YouTube reorders and renames the
///    containers regularly while leaving the leaf renderers alone, so nothing here
///    walks a long fixed path; it sweeps for renderers by name.
/// 2. **Document order is not available.** `JSONSerialization` produces unordered
///    dictionaries, so "the first one in the response" — which is how a scripting
///    language would pick — is not a thing Swift can ask for. Anywhere a response
///    carries several candidates, the right one is identified by *what it is* rather
///    than where it sits. `continuation(in:)` is the one that really matters.
enum Renderers {

    // MARK: - Tree walking

    /// Every dictionary in the tree stored at `key`.
    ///
    /// Unordered with respect to sibling dictionary keys — see the note above. Arrays
    /// are visited in order, which is what keeps a channel's videos in the order the
    /// channel lists them, because the items are always in an array.
    static func findAll(_ key: String, in node: Any) -> [[String: Any]] {
        var found: [[String: Any]] = []
        sweep(node) { object in
            if let match = object[key] as? [String: Any] { found.append(match) }
        }
        return found
    }

    /// Some value at `key` somewhere in the tree, coerced to `T`.
    ///
    /// Only safe where the key is unique in the subtree — `channelMetadataRenderer`,
    /// the `videoId` inside one item's tap command. Never use it to pick between
    /// candidates.
    static func findFirst<T>(_ key: String, in node: Any, as: T.Type = T.self) -> T? {
        var result: T?
        sweep(node) { object in
            guard result == nil else { return }
            if let value = object[key] as? T { result = value }
        }
        return result
    }

    /// Every value stored at `key` anywhere in the tree, coerced to `T`.
    ///
    /// Use this, not `findFirst`, whenever the response may hold several candidates and
    /// the right one is recognisable — a browse response carries both the channel's
    /// `UC…` id and a `FEwhat_to_watch` under the same key, and which of the two
    /// `findFirst` returns is not defined.
    static func findAllValues<T>(_ key: String, in node: Any, as: T.Type = T.self) -> [T] {
        var found: [T] = []
        sweep(node) { object in
            if let value = object[key] as? T { found.append(value) }
        }
        return found
    }

    private static func sweep(_ node: Any, _ visit: ([String: Any]) -> Void) {
        if let object = node as? [String: Any] {
            visit(object)
            for value in object.values { sweep(value, visit) }
        } else if let array = node as? [Any] {
            for value in array { sweep(value, visit) }
        }
    }

    /// The four ways InnerTube writes a piece of user-visible text — all of which occur
    /// in a single channel-tab response today.
    ///
    ///   `"Fireship"`                         a bare string
    ///   `{"simpleText": "Fireship"}`         the classic renderers
    ///   `{"runs": [{"text": "Fire"}, …]}`    anything with inline styling
    ///   `{"content": "Fireship"}`            the viewModel generation
    static func text(_ node: Any?) -> String? {
        if let string = node as? String { return string.isEmpty ? nil : string }
        guard let object = node as? [String: Any] else { return nil }
        if let simple = object["simpleText"] as? String, !simple.isEmpty { return simple }
        if let content = object["content"] as? String, !content.isEmpty { return content }
        if let runs = object["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            if !joined.isEmpty { return joined }
        }
        // `{"text": {"content": …}}` — the viewModel metadata-part wrapper.
        if let nested = object["text"] { return text(nested) }
        return nil
    }

    /// The token for the next page.
    ///
    /// A channel tab's response carries **six** continuation tokens: one for the grid,
    /// three for the "Latest / Popular / Oldest" filter chips, and two for a comment
    /// section. Picking the wrong one pages sideways into a different shelf, and since
    /// Swift cannot ask for the first in document order, the right one has to be
    /// identified structurally: it is the one hanging off a `continuationItemRenderer`
    /// — the chips hang off `chipViewModel` — and, when a response has several of
    /// those, the one inside the tab's own grid.
    static func continuation(in node: Any) -> String? {
        var scopes: [Any] = []
        if let grid = findFirst("richGridRenderer", in: node, as: [String: Any].self) {
            scopes.append(grid)
        }
        if let grid = findFirst("gridRenderer", in: node, as: [String: Any].self) {
            scopes.append(grid)
        }
        // A continuation response has no grid wrapper at all — its items arrive under
        // `appendContinuationItemsAction` — so the whole response is the last scope.
        scopes.append(node)

        for scope in scopes {
            let tokens = Set(findAll("continuationItemRenderer", in: scope)
                .compactMap { findFirst("token", in: $0, as: String.self) }
                .filter { !$0.isEmpty })
            if tokens.count == 1 { return tokens.first }
        }

        // Pre-viewModel shape, still served on some tabs.
        if let older = findFirst("nextContinuationData", in: node, as: [String: Any].self),
           let token = older["continuation"] as? String, !token.isEmpty {
            return token
        }
        return nil
    }

    // MARK: - Numbers

    /// "1.2M views" / "4.27 million subscribers" / "No views" -> an Int.
    ///
    /// The listing endpoints give counts as display text, not numbers — the exact figure
    /// only comes back on a video's own page, which is a request per row nobody wants.
    /// So the abbreviation is read back and `compactCount` re-abbreviates it for display.
    /// Round-tripping "1.2M" gives 1,200,000 rather than the true count, which is the
    /// right trade: the label reads the same and the ordering is preserved.
    ///
    /// Both spellings occur — a search result says "4.27 million subscribers" while a
    /// video says "623K views" — so the suffix and the word are both handled.
    static func count(from display: String?) -> Int? {
        guard let display else { return nil }
        let lowered = display.lowercased()
        if lowered.hasPrefix("no ") { return 0 }

        // The leading number, keeping one decimal point and dropping group separators.
        var digits = ""
        var index = lowered.startIndex
        while index < lowered.endIndex, !lowered[index].isNumber {
            index = lowered.index(after: index)
        }
        while index < lowered.endIndex {
            let character = lowered[index]
            if character.isNumber || character == "." { digits.append(character) }
            else if character != "," { break }
            index = lowered.index(after: index)
        }
        guard let value = Double(digits) else { return nil }

        let multiplier: Double
        if lowered.contains("billion") { multiplier = 1_000_000_000 }
        else if lowered.contains("million") { multiplier = 1_000_000 }
        else if lowered.contains("thousand") { multiplier = 1_000 }
        else {
            // A bare suffix: "1.2M", "623K". Read the first letter after the number.
            let suffix = lowered[index...].drop(while: { $0 == " " }).first
            switch suffix {
            case "b": multiplier = 1_000_000_000
            case "m": multiplier = 1_000_000
            case "k": multiplier = 1_000
            default:  multiplier = 1
            }
        }
        return Int((value * multiplier).rounded())
    }

    /// "12:34" or "1:02:03" -> seconds.
    static func seconds(from clock: String?) -> Int? {
        guard let clock, clock.contains(":") else { return nil }
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }
        var total = 0
        for part in parts {
            guard let value = Int(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// Widest image in either image list shape: `{"thumbnails": […]}` on the classic
    /// renderers, `{"sources": […]}` on the viewModel ones.
    static func image(_ node: Any?) -> URL? {
        guard let object = node as? [String: Any] else { return nil }
        let list = (object["thumbnails"] as? [[String: Any]])
            ?? (object["sources"] as? [[String: Any]])
        guard let list, !list.isEmpty else { return nil }
        let widest = list
            .filter { $0["url"] is String }
            .max { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        guard var string = widest?["url"] as? String, !string.isEmpty else { return nil }
        // Search results give these protocol-relative, which URL parses happily and
        // AsyncImage then fails to load.
        if string.hasPrefix("//") { string = "https:" + string }
        return URL(string: string)
    }

    // MARK: - Videos

    /// The classic leaf renderers. Channel tabs no longer use any of these — they moved
    /// to `lockupViewModel` — but search results and playlists still do.
    private static let classicVideoRenderers = [
        "videoRenderer",
        "gridVideoRenderer",
        "playlistVideoRenderer",
        "reelItemRenderer",
        "compactVideoRenderer",
    ]

    /// Every video in a response, de-duplicated.
    static func videos(in node: Any, channel: Channel?) -> [Video] {
        var seen = Set<String>()
        var result: [Video] = []

        func add(_ video: Video?) {
            guard let video, seen.insert(video.id).inserted else { return }
            result.append(video)
        }

        for lockup in findAll("shortsLockupViewModel", in: node) {
            add(shortsVideo(from: lockup, channel: channel))
        }
        for lockup in findAll("lockupViewModel", in: node) {
            add(lockupVideo(from: lockup, channel: channel))
        }
        for name in classicVideoRenderers {
            for renderer in findAll(name, in: node) {
                add(classicVideo(from: renderer, channel: channel))
            }
        }
        return result
    }

    /// The current channel-tab shape: title and views in a metadata block, duration in
    /// a badge on the thumbnail, and the video id at the top as `contentId`.
    private static func lockupVideo(from lockup: [String: Any], channel: Channel?) -> Video? {
        // The same renderer carries channels and playlists in search results, so the
        // type is checked rather than assumed. An absent type is treated as a video,
        // which is what the older responses that omit it were.
        if let type = lockup["contentType"] as? String,
           type != "LOCKUP_CONTENT_TYPE_VIDEO", type != "LOCKUP_CONTENT_TYPE_SHORT" {
            return nil
        }
        guard let id = lockup["contentId"] as? String, !id.isEmpty else { return nil }

        let metadata = findFirst("lockupMetadataViewModel", in: lockup, as: [String: Any].self)
        let title = text(metadata?["title"]) ?? id

        // "623K views" and "6 hours ago" arrive as sibling parts with nothing naming
        // which is which, so the one mentioning views is picked out by its text.
        var views: Int?
        for block in findAll("contentMetadataViewModel", in: lockup) {
            for row in block["metadataRows"] as? [[String: Any]] ?? [] {
                for part in row["metadataParts"] as? [[String: Any]] ?? [] {
                    guard let value = text(part), value.lowercased().contains("view") else { continue }
                    views = count(from: value)
                }
            }
        }

        var duration: Int?
        for badge in findAll("thumbnailBadgeViewModel", in: lockup) {
            guard duration == nil else { break }
            duration = seconds(from: badge["text"] as? String)
        }

        return Video(id: id, title: title, duration: duration, views: views,
                     channelName: channel?.title, channelId: channel?.id)
    }

    /// Shorts have their own shape again: no duration at all, and the title and view
    /// count in an overlay block rather than a metadata row.
    private static func shortsVideo(from lockup: [String: Any], channel: Channel?) -> Video? {
        var id = findFirst("videoId", in: lockup["onTap"] as Any, as: String.self)
        if id == nil, let entity = lockup["entityId"] as? String,
           entity.hasPrefix("shorts-shelf-item-") {
            id = String(entity.dropFirst("shorts-shelf-item-".count))
        }
        guard let id, !id.isEmpty else { return nil }

        let overlay = lockup["overlayMetadata"] as? [String: Any]
        return Video(
            id: id,
            title: text(overlay?["primaryText"]) ?? id,
            duration: nil,      // YouTube does not give one for a Short in a listing
            views: count(from: text(overlay?["secondaryText"])),
            channelName: channel?.title,
            channelId: channel?.id
        )
    }

    private static func classicVideo(from renderer: [String: Any], channel: Channel?) -> Video? {
        let id = (renderer["videoId"] as? String)
            ?? findFirst("videoId", in: renderer, as: String.self)
        guard let id, !id.isEmpty else { return nil }

        let duration = seconds(from: text(renderer["lengthText"]))
            ?? (renderer["lengthSeconds"] as? String).flatMap(Int.init)

        // Search results name their channel; a channel tab does not, because the whole
        // listing is one channel — which is what `channel` is passed in for.
        let ownerName = text(renderer["ownerText"])
            ?? text(renderer["longBylineText"])
            ?? text(renderer["shortBylineText"])
        let ownerID = findFirst("browseId", in: renderer["ownerText"] as Any, as: String.self)
            ?? findFirst("browseId", in: renderer["longBylineText"] as Any, as: String.self)

        return Video(
            id: id,
            title: text(renderer["title"]) ?? text(renderer["headline"]) ?? id,
            duration: duration,
            views: count(from: text(renderer["viewCountText"])
                ?? text(renderer["shortViewCountText"])),
            channelName: ownerName ?? channel?.title,
            channelId: ownerID ?? channel?.id
        )
    }

    // MARK: - Channels

    static func channels(in node: Any) -> [Channel] {
        var seen = Set<String>()
        var result: [Channel] = []

        for name in ["channelRenderer", "gridChannelRenderer"] {
            for renderer in findAll(name, in: node) {
                guard let channel = channel(from: renderer),
                      seen.insert(channel.id).inserted
                else { continue }
                result.append(channel)
            }
        }
        for lockup in findAll("lockupViewModel", in: node) {
            guard lockup["contentType"] as? String == "LOCKUP_CONTENT_TYPE_CHANNEL",
                  let id = lockup["contentId"] as? String, id.hasPrefix("UC"),
                  seen.insert(id).inserted
            else { continue }
            let metadata = findFirst("lockupMetadataViewModel", in: lockup, as: [String: Any].self)
            result.append(Channel(
                id: id,
                title: text(metadata?["title"]) ?? id,
                avatar: image(findFirst("image", in: lockup, as: [String: Any].self))
            ))
        }
        return result
    }

    static func channel(from renderer: [String: Any]) -> Channel? {
        let id = (renderer["channelId"] as? String)
            ?? findFirst("browseId", in: renderer, as: String.self)
        guard let id, id.hasPrefix("UC") else { return nil }

        // The two fields are not what they are called, and this is not a typo:
        // on a channel search result `subscriberCountText` holds the **handle**
        // ("@Fireship") and `videoCountText` holds the **subscriber count**
        // ("4.27 million subscribers"). Reading them by name gives a nil subscriber
        // count and throws the handle away. Verified live; see Tools/check-renderers.py.
        let subscriberField = text(renderer["subscriberCountText"])
        // The count is on the accessibility label when the visible text is abbreviated.
        let videoCountField = findFirst("label", in: renderer["videoCountText"] as Any, as: String.self)
            ?? text(renderer["videoCountText"])

        var handle = subscriberField?.hasPrefix("@") == true ? subscriberField : nil
        if handle == nil, let canonical = findFirst("canonicalBaseUrl", in: renderer, as: String.self) {
            let trimmed = canonical.hasPrefix("/") ? String(canonical.dropFirst()) : canonical
            if trimmed.hasPrefix("@") { handle = trimmed }
        }

        var subscribers: Int?
        for candidate in [videoCountField, subscriberField] {
            guard let candidate, candidate.lowercased().contains("subscriber") else { continue }
            subscribers = count(from: candidate)
            break
        }

        return Channel(
            id: id,
            title: text(renderer["title"]) ?? id,
            handle: handle,
            subscribers: subscribers,
            avatar: image(renderer["thumbnail"])
        )
    }

    /// What a channel's own browse response says about it — the avatar above all, since
    /// that is the one thing neither a listing nor a Takeout row carries.
    static func details(in node: Any) -> Channel.Details {
        // `channelMetadataRenderer` is the stable block and is unique in the response.
        // The visual header has been rewritten three times and is read only for the
        // subscriber count, which the metadata block does not carry.
        let metadata = findFirst("channelMetadataRenderer", in: node, as: [String: Any].self) ?? [:]
        let header = findFirst("pageHeaderViewModel", in: node, as: [String: Any].self)
            ?? findFirst("c4TabbedHeaderRenderer", in: node, as: [String: Any].self)
            ?? [:]

        // "http://www.youtube.com/@Fireship" -> "@Fireship"
        var handle: String?
        if let vanity = metadata["vanityChannelUrl"] as? String,
           let last = vanity.split(separator: "/").last, last.hasPrefix("@") {
            handle = String(last)
        }

        // The header's metadata parts are "@Fireship", "4.27M subscribers", "789 videos"
        // in no self-describing order, so the subscriber row is found by its own text.
        var subscribers: Int?
        for block in findAll("contentMetadataViewModel", in: header) {
            for row in block["metadataRows"] as? [[String: Any]] ?? [] {
                for part in row["metadataParts"] as? [[String: Any]] ?? [] {
                    guard let value = text(part),
                          value.lowercased().contains("subscriber") else { continue }
                    subscribers = count(from: value)
                }
            }
        }
        if subscribers == nil {
            subscribers = count(from: text(header["subscriberCountText"]))
        }

        return Channel.Details(
            avatar: image(metadata["avatar"])
                ?? image(findFirst("avatar", in: header, as: [String: Any].self)),
            subscribers: subscribers,
            handle: handle,
            title: (metadata["title"] as? String) ?? text(header["title"])
        )
    }
}
