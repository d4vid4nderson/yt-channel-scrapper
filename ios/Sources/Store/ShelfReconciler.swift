import Foundation
import os

/// Makes a minor's phone match its shelf: fetch what has been approved, delete what has
/// not, and never stream anything.
///
/// ## Why the child's device downloads rather than plays
///
/// Everything else in this app could have been solved by streaming. This could not.
/// Playing from YouTube means playing YouTube's ads, and the ads are the reason the app
/// exists — a downloaded file has none, because there is no request for an ad to be
/// served into. So the rule on a minor's device is absolute: **if it is not on disk, it
/// does not play.**
///
/// This class keeps the right things on the disk. It does **not** enforce the rule —
/// nothing stops a minor's device playing a `.stream` yet, and until `Playback` refuses
/// one in Minor Mode the ad-free guarantee rests on what the UI happens to offer rather
/// than on something the app actually holds to. That guard is the next thing to write,
/// and this note is here so the gap is not mistaken for a finished feature.
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
    func reconcile(
        for minor: Profiles.Minor,
        shelf: ShelfStore,
        downloads: Downloads,
        localFiles: LocalFiles
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

        lastSwept = sweep(keeping: allowed, localFiles: localFiles)
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
