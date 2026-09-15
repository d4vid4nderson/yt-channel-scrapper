import Foundation

/// What a minor is allowed to see, and the record of who decided it.
///
/// The app until now had one collection: the things you saved. That works for one person
/// curating for themselves, and stops working the moment two guardians curate for a
/// child. This is the second collection — the *approved set* — and it is deliberately
/// not a copy of the library. Approving something promotes it onto a shelf; it stays in
/// your own library too, and nothing about your library is visible to the other guardian.
///
/// ## Why this is not a `LibraryArchive` snapshot
///
/// `CloudMirror` mirrors the whole library as one value and takes the newest wholesale,
/// and its own notes say why that is right — a union cannot express a deletion, so a
/// removed channel would come back from the other device forever. They also say what it
/// costs: "for two people editing at once would not be."
///
/// A shelf *is* two people editing at once. So the unit here is the individual decision
/// rather than the whole set, and a removal is a record rather than an absence. Two
/// guardians can act between syncs and neither loses the other's edit, which whole-archive
/// last-writer-wins cannot promise.
///
/// ## The rules, stated plainly
///
/// 1. **Newest decision wins**, per item, not per shelf.
/// 2. **A removal beats an approval at the same instant.** Two phones' clocks are not the
///    same clock, and JSON truncates a `Date` on the way through, so equal timestamps are
///    reachable in practice rather than merely in theory. When it happens, the veto stands:
///    the cost of a wrongly-blocked video is that somebody re-approves it, and the cost of
///    a wrongly-allowed one is the thing this whole app exists to prevent.
/// 3. **Every decision carries who made it**, so the UI can say "Removed by Sarah on
///    Tuesday" rather than letting a video silently reappear and start an argument.
struct ShelfEntry: Codable, Hashable, Sendable {

    enum Kind: String, Codable, Sendable {
        case channel
        case video
    }

    enum State: String, Codable, Sendable {
        case approved
        case removed
    }

    /// What this decision is about: a `UC…` channel id, or an eleven-character video id.
    /// Which of the two is in `id` is `kind`'s job — the id spaces do not overlap, but
    /// relying on that to tell them apart would be a trick rather than a design.
    struct Key: Codable, Hashable, Sendable {
        let kind: Kind
        let id: String
    }

    let kind: Kind
    let id: String
    var state: State
    /// The display name of the guardian who decided, for attribution in the UI. A name
    /// rather than an id because it is shown far more often than it is compared, and the
    /// comparison it *is* used for — breaking a tie between two simultaneous decisions —
    /// only needs to be consistent, not meaningful.
    var guardian: String
    var at: Date

    /// What to call it. Carried on the entry so a minor's device can name a download and
    /// draw a row without asking YouTube anything — the whole point of that device is
    /// that it makes no listing calls at all.
    var title: String?

    /// For a video, the channel it came from. Optional because an entry written before
    /// this existed has none, and because a channel entry is its own id already.
    ///
    /// This is what lets vetoing a channel take its videos with it — see
    /// `ShelfMerge.playable`. Without it, blocking a channel would leave everything
    /// already approved from it sitting on the child's phone.
    var channelID: String?

    var key: Key { Key(kind: kind, id: id) }

    init(
        kind: Kind,
        id: String,
        state: State,
        guardian: String,
        at: Date = Date(),
        title: String? = nil,
        channelID: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.state = state
        self.guardian = guardian
        self.at = at
        self.title = title
        self.channelID = channelID
    }

    /// Whether this decision supersedes `other`. Only ever asked about two decisions on
    /// the same `key`; comparing across keys is meaningless and never happens.
    ///
    /// The third clause exists for determinism rather than for safety. Two guardians who
    /// approve the same video in the same instant produce the same shelf either way, but
    /// without a stable tiebreak the two phones could disagree about *whose name to show*
    /// next to it, which reads as a sync bug even though the shelf is correct.
    func supersedes(_ other: ShelfEntry) -> Bool {
        if at != other.at { return at > other.at }
        if state != other.state { return state == .removed }
        return guardian > other.guardian
    }
}

// MARK: - Merging

/// The pure half of the shelf: given every decision from every guardian, what does the
/// minor actually get?
///
/// Deliberately free of files, iCloud and dates-from-now, because it is the part that has
/// to be right. `ShelfStore` puts it on disk; this decides what the answer is.
enum ShelfMerge {

    /// The surviving decision for each item, from any number of guardians' files fed in
    /// in any order. Order-independence is the property that matters: two phones that
    /// read the same files in different orders must land on the same shelf.
    static func resolve(_ entries: some Sequence<ShelfEntry>) -> [ShelfEntry.Key: ShelfEntry] {
        var winners: [ShelfEntry.Key: ShelfEntry] = [:]
        for entry in entries {
            guard let standing = winners[entry.key] else {
                winners[entry.key] = entry
                continue
            }
            if entry.supersedes(standing) { winners[entry.key] = entry }
        }
        return winners
    }

    /// Just the keys a minor may see. This is what the reconciler diffs against the
    /// files already on the device, and what the minor's UI draws.
    static func approved(_ entries: some Sequence<ShelfEntry>) -> Set<ShelfEntry.Key> {
        Set(resolve(entries).values.filter { $0.state == .approved }.map(\.key))
    }

    /// The videos a minor may actually be given, which is not quite the approved set.
    ///
    /// A video is playable when its own standing decision is `approved` **and** the
    /// channel it came from is not currently `removed`. The second half is what makes
    /// "block this channel" mean something: a parent who blocks a channel expects what
    /// is already on the phone to go too, not just for the next video to be kept out.
    ///
    /// Note the asymmetry — approving a *channel* does not approve its videos. Nothing
    /// reaches a child without a decision naming the thing itself, so a channel that
    /// posts something new cannot push it onto the phone unseen. A channel approval is a
    /// note between guardians that the channel is fine, and a shortcut in the parent's
    /// UI for approving from it; a channel *removal* is a veto with teeth.
    static func playable(_ entries: some Sequence<ShelfEntry>) -> [ShelfEntry] {
        let standing = resolve(entries)
        let blockedChannels = Set(
            standing.values
                .filter { $0.kind == .channel && $0.state == .removed }
                .map(\.id)
        )
        return standing.values
            .filter { entry in
                guard entry.kind == .video, entry.state == .approved else { return false }
                guard let channelID = entry.channelID else { return true }
                return !blockedChannels.contains(channelID)
            }
            .sorted { $0.at > $1.at }
    }

    /// One guardian's own file, reduced to their current opinion.
    ///
    /// A guardian's decisions about a single item are totally ordered — they are all from
    /// the same person on the same device — so everything before their latest carries no
    /// information and is dropped on write. This is the only pruning that happens, and it
    /// is safe precisely because it never touches anybody else's decision.
    ///
    /// ## Why old tombstones are never pruned
    ///
    /// The obvious next optimisation is to drop `removed` entries after some months. It
    /// is a trap, and worth writing down so nobody adds it later:
    ///
    /// > David approves a video. Sarah removes it. Ninety days pass and Sarah's phone
    /// > drops her tombstone as stale. Now David's approval is the only decision left,
    /// > it wins by default, and the video returns to the child's device.
    ///
    /// A tombstone is not stale data, it is the entire representation of a veto, and it
    /// has to outlive the approval it overrides — which means outliving it indefinitely,
    /// because there is no local way to know the other file will not reappear. The cost
    /// of keeping them is nil at this scale: an entry is about 120 bytes of JSON, and a
    /// family that decides ten things a week for a decade fills half a megabyte.
    static func collapsed(_ entries: some Sequence<ShelfEntry>) -> [ShelfEntry] {
        resolve(entries).values.sorted { left, right in
            if left.at != right.at { return left.at > right.at }
            return left.id < right.id
        }
    }
}

// MARK: - On disk

/// One guardian's decisions about one minor: the unit that gets written to iCloud Drive.
///
/// The sync design is "each device writes only the file it owns, and merges everything it
/// reads." Two guardians and two children is four files, none of which is ever written by
/// more than one device — so there is no write conflict to coordinate, no `NSFileCoordinator`
/// dance, and no way for one phone to clobber the other's decisions. Convergence is
/// `ShelfMerge`'s job, on read, on every device.
struct ShelfFile: Codable, Sendable {
    /// Stable across a rename, so the file keeps its identity when a guardian changes
    /// their display name.
    let guardianID: UUID
    var guardianName: String
    let minorID: UUID
    /// Carried in every file so the roster of children needs no file of its own.
    ///
    /// A separate `family.json` would be a second thing two devices write to, which is
    /// the exact conflict this layout exists to avoid. Instead the children *are* the
    /// distinct `minorID`s across the folder, and a rename is settled by `writtenAt` the
    /// same way everything else here is settled by a timestamp. Creating a child writes
    /// an empty file, which is what puts them on the roster before anything is approved.
    var minorName: String
    var writtenAt: Date
    var entries: [ShelfEntry]

    /// `kid1-1F2E….json`. The minor comes first so a folder listing groups by child,
    /// which is how a parent reads it when something has gone wrong.
    static func filename(minorID: UUID, guardianID: UUID) -> String {
        "\(minorID.uuidString)-\(guardianID.uuidString).json"
    }

    var filename: String { Self.filename(minorID: minorID, guardianID: guardianID) }
}
