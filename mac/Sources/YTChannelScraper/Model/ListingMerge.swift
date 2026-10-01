import Foundation

/// Folding a fresh read of a channel's newest videos onto the list kept from last time.
///
/// Both apps keep each channel tab on disk and, on a refresh, read only its head — the
/// first page or two — rather than walking the whole catalogue again. That head is
/// newest-first, like the kept list, so a refresh is a splice: what is new goes on top,
/// what was already there keeps its place below.
///
/// Shared by the Mac and the iPhone (it lives in `Model/`, which both compile), because
/// the rule is the same however the head was read — yt-dlp on one, InnerTube on the other.
enum ListingMerge {
    struct Result: Equatable {
        var videos: [Video]
        /// How many of `videos` were not in the kept list.
        var added: Int
    }

    /// Splice `head` onto `kept`, or nil when the two do not meet.
    ///
    /// Nil means every video in the head is new, so there may be more new ones beyond it
    /// that it does not reach: splicing then would leave a silent hole in the middle of the
    /// list. The caller reads further and asks again, or, out of patience, starts the list
    /// over from the head.
    ///
    /// Inside the stretch the head covers — down to the deepest kept video it still lists
    /// — a kept video the head no longer lists has been deleted or made private, and is
    /// dropped. Below that stretch the head says nothing, so everything kept stays.
    /// Where both have a video, the head's copy wins: view counts and titles move on.
    static func splice(_ head: [Video], onto kept: [Video]) -> Result? {
        guard !head.isEmpty else { return Result(videos: kept, added: 0) }
        guard !kept.isEmpty else { return Result(videos: head, added: head.count) }

        let headIDs = Set(head.map(\.id))
        guard let deepest = kept.lastIndex(where: { headIDs.contains($0.id) }) else { return nil }

        let keptIDs = Set(kept.map(\.id))
        let below = kept[(deepest + 1)...].filter { !headIDs.contains($0.id) }
        return Result(videos: head + below,
                      added: head.filter { !keptIDs.contains($0.id) }.count)
    }
}
