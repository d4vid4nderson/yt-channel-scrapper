import Foundation
import os

/// Makes a minor's phone match its shelf: fetch what has been approved, delete what has
/// not, and never stream anything.
///
/// ## Why the child's device downloads rather than streams
///
/// **Not because of ads.** An earlier version of this comment said streaming meant
/// YouTube's ads, and that is wrong about this app. Ads are inserted by YouTube's own
/// player; the sanctioned IFrame player in a `WKWebView` would carry them, which is why
/// that route was rejected. This app never uses it — `StreamResolver` asks InnerTube for
/// `streamingData` and hands the resulting URLs straight to `AVPlayer`, which plays media
/// bytes and nothing else. Streaming here is already ad-free, and has been in testing.
///
/// The reasons that do hold are quieter and worth keeping straight, because one of them
/// is about correctness rather than preference:
///
/// - **It works with no network.** A car, a plane, a school with the WiFi locked down.
/// - **The child's device never talks to YouTube.** Every entry carries its own title, so
///   that device makes no listing calls at all and nothing is logged against them.
/// - **A stream might simply not resolve.** See `StreamResolver`'s own notes: every client
///   in the ladder can come back "Sign in to confirm you're not a bot". A file on disk
///   cannot fail that way.
/// - **A file is what was approved.** A stream is re-fetched each time.
///
/// So this class keeps the approved things on disk, which is worth doing on all four
/// counts. Whether a minor's device should additionally *refuse* to stream is a product
/// decision and not a safety hole — nothing currently stops it, and that is no longer
/// filed as a bug.
///
/// The side effects are all the good kind. The phone works in the car, on a plane and at
/// school, because nothing it plays needs a network. And it makes no listing calls to
/// YouTube at all — every entry carries its own title, so the child's device only ever
/// asks for the bytes of a specific, named, already-approved video.
///
/// ## What a removal has to do
///
/// Un-approving something has to reach a file that is already on the phone, or the veto
/// is decorative. `sweep` deletes it. That is the half of this that is easy to leave out
/// and the half a parent will actually test.
@MainActor
@Observable
final class ShelfReconciler {

    private(set) var lastRun: Date?
    private(set) var isRunning = false
    /// Approved but not yet on disk. What the minor's empty state counts down.
    private(set) var awaiting = 0
    /// Files removed on the last pass, so the UI can say why something went away.
    private(set) var lastSwept = 0

    /// What the child's phone fetches at. Fixed rather than offered: the picker is a
    /// parent's tool and this device has no parent holding it.
    private let quality: Quality

    init(quality: Quality = .p720) {
        self.quality = quality
    }

    /// Bring the phone in line with the shelf. Safe to call on every foreground and
    /// after every refresh — it is a diff, so a pass with nothing to do costs a scan.
    /// - Parameter sweeping: whether to delete local files that are no longer approved.
    ///   True on a minor's device, where an un-approval has to reach a file that is
    ///   already there or the veto is decorative. **False on an admin's**, where the
    ///   local files are their own library and the shelf is only a list of things other
    ///   people have sent them — sweeping there would delete what nobody vetoed.
    func reconcile(
        for minor: Profiles.Minor,
        shelf: ShelfStore,
        downloads: Downloads,
        localFiles: LocalFiles,
        sweeping: Bool = true
    ) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // A shelf that could not be read is not an empty shelf. `ShelfStore.refresh`
        // keeps the last good copy for exactly this reason: acting on a failed read
        // would delete everything the child has.
        let entries = shelf.entries(for: minor.id)
        guard !entries.isEmpty || shelf.lastRead != nil else {
            Log.shelf.notice("no shelf read yet; skipping reconcile")
            return
        }

        let playable = ShelfMerge.playable(entries)
        let allowed = Set(playable.map(\.id))

        lastSwept = sweeping ? sweep(keeping: allowed, localFiles: localFiles) : 0
        awaiting = fetch(playable, downloads: downloads, localFiles: localFiles)
        lastRun = Date()
    }

    // MARK: - Removing

    /// Delete anything on disk the shelf no longer allows.
    ///
    /// Only ever touches files whose `videoID` could be read from the name. A file the
    /// user put in the folder themselves has none, plays fine, and is not this
    /// function's business — deleting somebody's own audiobook because it was not on a
    /// YouTube shelf would be a bug with no way to undo it.
    @discardableResult
    private func sweep(keeping allowed: Set<String>, localFiles: LocalFiles) -> Int {
        let doomed = localFiles.files.filter { file in
            guard let videoID = file.videoID else { return false }
            return !allowed.contains(videoID)
        }
        for file in doomed {
            Log.shelf.notice("sweeping \(file.videoID ?? "?", privacy: .public): no longer approved")
            localFiles.delete(file)
        }
        return doomed.count
    }

    // MARK: - Fetching

    /// Queue everything approved that is not already here or already coming.
    /// Returns how many are still outstanding.
    private func fetch(
        _ playable: [ShelfEntry],
        downloads: Downloads,
        localFiles: LocalFiles
    ) -> Int {
        let onDisk = Set(localFiles.files.compactMap(\.videoID))
        let inFlight = Set(
            downloads.jobs.filter { !$0.state.isFinished }.map(\.video.id)
        )

        let missing = playable.filter { !onDisk.contains($0.id) && !inFlight.contains($0.id) }
        let videos = missing.compactMap(Self.video(from:))
        if !videos.isEmpty {
            Log.shelf.notice("fetching \(videos.count) newly approved item(s)")
            downloads.enqueue(videos, quality: quality, alsoAudio: false)
        }
        return playable.filter { !onDisk.contains($0.id) }.count
    }

    /// Rebuild the `Video` a download needs from the entry alone.
    ///
    /// Through `init?(json:)` rather than a memberwise init because `Video` lives in
    /// `mac/` and nothing under `mac/` is modified by the iOS target — a rule the project
    /// states twice and which is worth more than the tidier constructor would be. The
    /// keys are the ones that init already reads.
    private static func video(from entry: ShelfEntry) -> Video? {
        var json: [String: Any] = ["id": entry.id]
        // Falling back to the id matches what `Video.init?(json:)` does with a missing
        // title, so a pre-title entry names its file the same way it always would have.
        json["title"] = entry.title ?? entry.id
        if let channelID = entry.channelID { json["channel_id"] = channelID }
        return Video(json: json)
    }
}
