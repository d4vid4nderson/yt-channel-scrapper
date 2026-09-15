import Foundation
import os

/// The shelf on disk: a folder in iCloud Drive that both guardians can reach.
///
/// ## Why a folder the user picks, and not iCloud
///
/// `CloudMirror` uses `NSUbiquitousKeyValueStore`, which is scoped to one Apple ID. That
/// is exactly right for a personal library — it follows you across your own devices and
/// nobody else can see it — and exactly wrong for a shelf, which two adults with two
/// Apple IDs both have to write to.
///
/// iOS offers no API to create a shared iCloud Drive folder or to invite anybody to one:
/// sharing is something a person does in Files.app, and an app can only be handed the
/// result. So setup is necessarily manual once — one guardian makes a folder and shares
/// it, both point the app at it — and this class holds the bookmark that survives that.
///
/// ## The layout, and why there is nothing to lock
///
/// ```
/// <shared folder>/
///   <minor>-<david>.json     ← only David's phone ever writes this
///   <minor>-<sarah>.json     ← only Sarah's phone ever writes this
/// ```
///
/// Every device writes one file per child and reads all of them. Because no file has two
/// writers, there is no write conflict to coordinate, nothing to lock, and no way for one
/// phone to land on top of the other's decisions — the worst case is that a file is stale,
/// and a stale file is just an older decision, which `ShelfMerge` already knows what to do
/// with. Convergence happens on read, on every device, rather than being negotiated.
///
/// A file is identified by what is *inside* it rather than by its name. The name only has
/// to be unique, which `ShelfFile.filename` guarantees; trusting it for identity would
/// mean a rename in Files.app could silently reassign a child's shelf.
@MainActor
@Observable
final class ShelfStore {

    /// The folder, once a bookmark has resolved. Nil before setup, and nil again if the
    /// folder is deleted or unshared out from under the app.
    private(set) var folder: URL?

    /// Every child any guardian has created, newest name wins. Derived from the files
    /// rather than stored, so adding a child needs no coordination either.
    private(set) var roster: [Profiles.Minor] = []

    /// What the user should be told, if anything. Nil when it is quietly working.
    private(set) var problem: String?

    private(set) var lastRead: Date?
    private(set) var isReading = false

    /// Everything read on the last pass, from all guardians.
    private var files: [ShelfFile] = []

    private static let bookmarkKey = "shelf.folder.bookmark"

    init() {
        resolveBookmark()
    }

    // MARK: - Where the folder is

    /// Take the folder the user picked and remember it across launches.
    ///
    /// Returns whether the bookmark was stored. A false here means the next launch would
    /// come back to no folder at all, which the setup screen has to say rather than
    /// report success and lose the choice.
    @discardableResult
    func adopt(_ picked: URL) -> Bool {
        // The picker hands back a URL that is only usable inside a security scope, and
        // the bookmark has to be taken while that scope is open.
        let opened = picked.startAccessingSecurityScopedResource()
        defer { if opened { picked.stopAccessingSecurityScopedResource() } }

        do {
            let bookmark = try picked.bookmarkData()
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            folder = picked
            problem = nil
            return true
        } catch {
            Log.shelf.error("could not bookmark \(picked.lastPathComponent, privacy: .public): \(error)")
            problem = "That folder could not be saved. Try picking it again."
            return false
        }
    }

    /// Forget the folder. The decisions themselves are in iCloud and are not touched —
    /// this only stops *this device* looking at them.
    func forgetFolder() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        folder = nil
        files = []
        roster = []
        problem = nil
    }

    private func resolveBookmark() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark,
                              bookmarkDataIsStale: &stale)
            folder = url
            // A stale bookmark still resolves; it just will not keep resolving. Rewriting
            // it now is the difference between a folder that keeps working and one that
            // stops on some future launch with nothing to explain it.
            if stale, url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let fresh = try? url.bookmarkData() {
                    UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
                }
            }
        } catch {
            Log.shelf.error("shelf folder bookmark did not resolve: \(error)")
            problem = "The shared folder could not be opened. Pick it again in Settings."
        }
    }

    // MARK: - Reading

    /// Re-read every guardian's file. Cheap enough to call on every foreground — the
    /// files are a few kilobytes and there are as many of them as there are adults times
    /// children.
    func refresh() async {
        guard let folder, !isReading else { return }
        isReading = true
        defer { isReading = false }

        let read = await Task.detached { Self.readAll(in: folder) }.value
        switch read {
        case .success(let found):
            files = found
            roster = Self.roster(from: found)
            problem = nil
            lastRead = Date()
        case .failure(let error):
            Log.shelf.error("shelf read failed: \(error)")
            // Deliberately does not clear `files`. Losing the folder for a moment — a
            // network blip, a file still downloading — must not empty a child's shelf,
            // because the reconciler would take that as "everything was un-approved" and
            // delete what is on the device.
            problem = "Could not read the shared folder just now."
        }
    }

    /// Every decision about one child, from every guardian.
    func entries(for minorID: UUID) -> [ShelfEntry] {
        files.filter { $0.minorID == minorID }.flatMap(\.entries)
    }

    /// What this child is allowed to see, after every guardian's decisions are merged.
    func approved(for minorID: UUID) -> Set<ShelfEntry.Key> {
        ShelfMerge.approved(entries(for: minorID))
    }

    /// The standing decision about one item, for a row that wants to show who made it.
    func decision(for key: ShelfEntry.Key, minorID: UUID) -> ShelfEntry? {
        ShelfMerge.resolve(entries(for: minorID))[key]
    }

    // MARK: - Writing

    /// Record decisions in this guardian's own file, leaving every other file alone.
    ///
    /// Takes an array because approving a channel and its videos is one gesture in the
    /// UI and should be one write here.
    @discardableResult
    func record(
        _ decisions: [ShelfEntry],
        for minor: Profiles.Minor,
        as guardian: Profiles.Guardian
    ) async -> Bool {
        guard !decisions.isEmpty else { return true }
        guard let folder else {
            problem = "No shared folder is set up yet."
            return false
        }

        // Start from what this guardian already has on file, so a decision made on the
        // other phone since the last read is not dropped from *their* file — it never
        // was in this one.
        let mine = files.first { $0.minorID == minor.id && $0.guardianID == guardian.id }
        let combined = ShelfMerge.collapsed((mine?.entries ?? []) + decisions)

        let file = ShelfFile(
            guardianID: guardian.id,
            guardianName: guardian.name,
            minorID: minor.id,
            minorName: minor.name,
            writtenAt: Date(),
            entries: combined
        )

        let wrote = await Task.detached { Self.write(file, in: folder) }.value
        guard wrote else {
            problem = "Could not save to the shared folder."
            return false
        }

        // Publish locally without waiting for a re-read, so the UI moves when tapped.
        files.removeAll { $0.minorID == minor.id && $0.guardianID == guardian.id }
        files.append(file)
        roster = Self.roster(from: files)
        problem = nil
        return true
    }

    /// Approve or remove one item. The common case, and the one the row buttons call.
    @discardableResult
    func set(
        _ state: ShelfEntry.State,
        kind: ShelfEntry.Kind,
        id: String,
        for minor: Profiles.Minor,
        as guardian: Profiles.Guardian
    ) async -> Bool {
        await record(
            [ShelfEntry(kind: kind, id: id, state: state, guardian: guardian.name)],
            for: minor,
            as: guardian
        )
    }

    /// Put a new child on the roster by writing an empty shelf for them.
    ///
    /// An empty file rather than a roster entry somewhere, because the roster *is* the
    /// set of files — see `ShelfFile.minorName`. It also means the child exists on both
    /// guardians' phones as soon as iCloud catches up, with nothing to invite or accept.
    func createMinor(named name: String, as guardian: Profiles.Guardian) async -> Profiles.Minor? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let folder else { return nil }

        let minor = Profiles.Minor(id: UUID(), name: trimmed)
        let file = ShelfFile(
            guardianID: guardian.id,
            guardianName: guardian.name,
            minorID: minor.id,
            minorName: minor.name,
            writtenAt: Date(),
            entries: []
        )
        guard await Task.detached(operation: { Self.write(file, in: folder) }).value else {
            problem = "Could not save to the shared folder."
            return nil
        }
        files.append(file)
        roster = Self.roster(from: files)
        return minor
    }

    // MARK: - The roster

    /// One entry per distinct child, named by whoever wrote most recently.
    ///
    /// A rename is therefore last-writer-wins, which is the one place in this design that
    /// rule is still the right one: a name is cosmetic, both guardians see the same one
    /// within a sync, and the id it hangs off never moves.
    private static func roster(from files: [ShelfFile]) -> [Profiles.Minor] {
        var newest: [UUID: ShelfFile] = [:]
        for file in files {
            if let standing = newest[file.minorID], standing.writtenAt >= file.writtenAt { continue }
            newest[file.minorID] = file
        }
        return newest.values
            .map { Profiles.Minor(id: $0.minorID, name: $0.minorName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - File I/O

    /// Off the main actor: iCloud Drive reads can block on a download.
    private nonisolated static func readAll(in folder: URL) -> Result<[ShelfFile], Error> {
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }

        do {
            let names = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
                options: [.skipsHiddenFiles]
            )

            var found: [ShelfFile] = []
            for url in names where url.pathExtension.lowercased() == "json" {
                // A file the other guardian wrote may still be a placeholder on this
                // device. Asking for it is not the same as having it — a file that is
                // still arriving is skipped this pass and picked up by the next refresh,
                // which is why a failed read must never be treated as an empty shelf.
                if !materialise(url) { continue }
                guard let data = try? Data(contentsOf: url),
                      let file = try? decoder.decode(ShelfFile.self, from: data)
                else {
                    Log.shelf.error("unreadable shelf file \(url.lastPathComponent, privacy: .public)")
                    continue
                }
                found.append(file)
            }
            return .success(found)
        } catch {
            return .failure(error)
        }
    }

    /// Ensure a file's contents are actually here, rather than a stub iCloud will fetch
    /// on demand. Returns whether it is readable now.
    private nonisolated static func materialise(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ])
        guard values?.isUbiquitousItem == true else { return true }   // a plain local file
        if values?.ubiquitousItemDownloadingStatus == .current { return true }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return false
    }

    private nonisolated static func write(_ file: ShelfFile, in folder: URL) -> Bool {
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }

        guard let data = try? encoder.encode(file) else { return false }
        let url = folder.appendingPathComponent(file.filename)

        var coordinationError: NSError?
        var wrote = false
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { destination in
            do {
                try data.write(to: destination, options: .atomic)
                wrote = true
            } catch {
                Log.shelf.error("shelf write failed: \(error)")
            }
        }
        if let coordinationError {
            Log.shelf.error("shelf write coordination failed: \(coordinationError)")
        }
        return wrote
    }

    /// ISO-8601 on both sides, matching what the merge rules were tested against — and
    /// readable in Files.app, which is the only debugger anyone has for a synced folder.
    private nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension Log {
    /// The shared folder: what was read, what was written, and what would not open.
    static let shelf = Logger(subsystem: "com.d4vid4nderson.ytchannelscraper",
                              category: "shelf")
}
