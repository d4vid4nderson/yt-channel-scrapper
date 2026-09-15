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

    /// Every adult who has written anything into this folder, derived the same way and
    /// for the same reason. There is no roster file for guardians and there must not be:
    /// a second file two devices write to is exactly what this layout avoids.
    private(set) var guardians: [Profiles.Guardian] = []

    /// Every device that has the app and has announced itself, newest report per device.
    private(set) var devices: [DeviceRecord] = []

    /// What the user should be told, if anything. Nil when it is quietly working.
    private(set) var problem: String?

    private(set) var lastRead: Date?
    private(set) var isReading = false

    /// Everything read on the last pass, from all guardians.
    private var files: [ShelfFile] = []
    /// The people each guardian has added, one file per guardian.
    private var peopleFiles: [PeopleFile] = []

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
        // Read regardless of how the shelf read went: the device list is a nice-to-have
        // and must never be the reason a shelf read counts as failed.
        let reported = await Task.detached { Self.readDevices(in: folder) }.value
        let declaredPeople = await Task.detached { Self.readPeople(in: folder) }.value
        switch read {
        case .success(let found):
            files = found
            peopleFiles = declaredPeople
            devices = reported
            recompute()
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
        as guardian: Profiles.Guardian,
        evenIfEmpty: Bool = false
    ) async -> Bool {
        guard !decisions.isEmpty || evenIfEmpty else { return true }
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
        recompute()
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

    /// Add somebody to the family: another parent, or a child.
    ///
    /// A child also gets an empty shelf written for them, which is what puts them on the
    /// roster and gives the other guardian something to approve into. A parent gets only
    /// the entry — there is nothing to approve *for* a parent — and stays unclaimed until
    /// a device says "I am them".
    @discardableResult
    func createPerson(named name: String, isMinor: Bool,
                      as guardian: Profiles.Guardian) async -> FamilyMember? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, folder != nil else { return nil }

        let member = FamilyMember(id: UUID(), name: trimmed, isMinor: isMinor)
        guard await write(member, as: guardian) else { return nil }

        if isMinor {
            await record([], for: Profiles.Minor(id: member.id, name: member.name),
                         as: guardian, evenIfEmpty: true)
        }
        return member
    }

    /// Take somebody out of the family.
    ///
    /// Writes a tombstone into this guardian's own file rather than deleting anything.
    /// Each guardian writes only their own file, so removing somebody the *other* parent
    /// added cannot be done by deletion — it has to be a removal that outlives the entry
    /// it overrides, exactly as a shelf veto does.
    ///
    /// Nothing they were part of is destroyed: a child's shelf files stay where they are,
    /// and past approvals keep the name they were signed with. Re-adding the same name
    /// later makes a new person, because the id is what everything is keyed on.
    @discardableResult
    func removePerson(_ id: UUID, as guardian: Profiles.Guardian) async -> Bool {
        guard id != guardian.id else { return false }   // never yourself

        // Refuse rather than invent. Removing somebody who is already gone — a double
        // click, a stale row — used to write a tombstone named "Removed" with the wrong
        // role into a file both parents read.
        let known = declared.first { $0.id == id }
        let name = known?.name
            ?? roster.first { $0.id == id }?.name
            ?? guardians.first { $0.id == id }?.name
        guard let name else { return false }

        let isMinor = known?.isMinor ?? roster.contains { $0.id == id }
        var stone = FamilyMember(id: id, name: name, isMinor: isMinor)
        stone.isRemoved = true
        return await write(stone, as: guardian)
    }

    /// Change somebody between parent and child after the fact.
    ///
    /// Writes the corrected entry into this guardian's own file; the union's newest-wins
    /// rule does the rest. A child promoted to parent keeps their shelf files — nothing
    /// is deleted — they simply stop being somebody you can send to, and `recompute`
    /// takes them out of the roster even though those files still name them.
    @discardableResult
    func setRole(_ id: UUID, isMinor: Bool, as guardian: Profiles.Guardian) async -> Bool {
        guard id != guardian.id else { return false }
        let existing = declared.first { $0.id == id }
        let name = existing?.name
            ?? roster.first { $0.id == id }?.name
            ?? guardians.first { $0.id == id }?.name
        guard let name else { return false }
        var member = FamilyMember(id: id, name: name, isMinor: isMinor)
        member.isClaimed = existing?.isClaimed ?? false
        return await write(member, as: guardian)
    }

    /// Record what device somebody is expected to have.
    ///
    /// Nil clears it. Writes the whole member back, so the role and claimed state survive
    /// — a partial write here would silently demote somebody.
    @discardableResult
    func setExpectedDevice(_ id: UUID, kind: DeviceRecord.Kind?,
                           as guardian: Profiles.Guardian) async -> Bool {
        let known = declared.first { $0.id == id }
        let name = known?.name
            ?? roster.first { $0.id == id }?.name
            ?? guardians.first { $0.id == id }?.name
        guard let name else { return false }

        var member = FamilyMember(
            id: id,
            name: name,
            isMinor: known?.isMinor ?? roster.contains { $0.id == id }
        )
        member.isClaimed = known?.isClaimed ?? false
        member.expectedKind = kind?.rawValue
        return await write(member, as: guardian)
    }

    /// What an admin said this person carries, if anything.
    func expectedDevice(for id: UUID) -> DeviceRecord.Kind? {
        declared.first { $0.id == id }?.expected
    }

    /// Mark a person as claimed, so the list stops saying nobody is using that identity.
    func markClaimed(_ id: UUID, as guardian: Profiles.Guardian) async {
        guard var mine = peopleFiles.first(where: { $0.guardianID == guardian.id }),
              let index = mine.people.firstIndex(where: { $0.id == id }),
              !mine.people[index].isClaimed
        else { return }
        mine.people[index].isClaimed = true
        mine.writtenAt = Date()
        await commit(mine)
    }

    private func write(_ member: FamilyMember, as guardian: Profiles.Guardian) async -> Bool {
        var mine = peopleFiles.first { $0.guardianID == guardian.id }
            ?? PeopleFile(guardianID: guardian.id, writtenAt: Date(), people: [])
        mine.people.removeAll { $0.id == member.id }
        mine.people.append(member)
        mine.writtenAt = Date()
        return await commit(mine)
    }

    @discardableResult
    private func commit(_ file: PeopleFile) async -> Bool {
        guard let folder else { return false }
        let wrote = await Task.detached { Self.write(file, in: folder) }.value
        guard wrote else {
            problem = "Could not save to the shared folder."
            return false
        }
        peopleFiles.removeAll { $0.guardianID == file.guardianID }
        peopleFiles.append(file)
        recompute()
        return true
    }

    /// Everyone, from both sources: who has written shelf files, and who has been added
    /// by name. Union rather than either alone — a parent who has approved things is real
    /// even if nobody added them, and one who was added is real before they approve.
    private func recompute() {
        var adults: [UUID: Profiles.Guardian] = [:]
        for g in Self.guardians(from: files) { adults[g.id] = g }
        var children: [UUID: Profiles.Minor] = [:]
        for m in Self.roster(from: files) { children[m.id] = m }

        // Somebody who has *written* a file is an admin, whatever a file addressed *to*
        // them might imply. A shelf file is `<recipientID>-<senderID>`, and since admins
        // can be sent things too, being a recipient no longer means being a minor — so
        // without this, sending a video to another admin turned them into one.
        for id in adults.keys { children[id] = nil }

        for member in declared {
            // A tombstone removes them from both halves, including when they would
            // otherwise be derived from the shelf files they have written. Those files
            // are left alone — this hides the person, it does not destroy their history.
            guard !member.removed else {
                adults[member.id] = nil
                children[member.id] = nil
                continue
            }
            // The declared role is authoritative, so it has to clear the other bucket:
            // a child promoted to parent still has shelf files carrying their name, and
            // `roster(from:)` would keep deriving them as a child from those.
            if member.isMinor {
                adults[member.id] = nil
                children[member.id] = Profiles.Minor(id: member.id, name: member.name)
            } else {
                children[member.id] = nil
                adults[member.id] = Profiles.Guardian(id: member.id, name: member.name)
            }
        }

        guardians = adults.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        roster = children.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// What the household is called, as most recently set by any admin.
    var familyName: String {
        peopleFiles
            .filter { $0.familyName?.isEmpty == false }
            .max { $0.writtenAt < $1.writtenAt }?
            .familyName ?? ""
    }

    @discardableResult
    func setFamilyName(_ name: String, as guardian: Profiles.Guardian) async -> Bool {
        var mine = peopleFiles.first { $0.guardianID == guardian.id }
            ?? PeopleFile(guardianID: guardian.id, writtenAt: Date(), people: [])
        mine.familyName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        mine.writtenAt = Date()
        return await commit(mine)
    }

    /// Everyone anybody has added, newest entry per id.
    ///
    /// A removal beats an addition written at the same instant — the same tiebreak the
    /// shelf uses, and for the same reason: dates go through JSON as ISO-8601, which
    /// truncates sub-second precision, so two edits moments apart can come back equal.
    /// Without it, removing somebody would be a coin flip.
    var declared: [FamilyMember] {
        var newest: [UUID: (FamilyMember, Date)] = [:]
        for file in peopleFiles {
            for member in file.people {
                if let standing = newest[member.id] {
                    if standing.1 > file.writtenAt { continue }
                    if standing.1 == file.writtenAt && standing.0.removed { continue }
                }
                newest[member.id] = (member, file.writtenAt)
            }
        }
        return newest.values.map(\.0)
    }

    /// Whether nobody has used this identity yet — a name typed by an admin that no
    /// device has adopted.
    ///
    /// Information, not permission. It used to gate the "this is me" action, which meant
    /// the one identity worth adopting — the one that has been doing the approving — was
    /// the only one that could not be. Somebody adding their second device is the common
    /// case, not an edge one.
    func isUnclaimed(_ id: UUID) -> Bool {
        guard let member = declared.first(where: { $0.id == id }) else { return false }
        if member.isClaimed { return false }
        // Having written anything is proof enough that somebody is using it.
        return !files.contains { $0.guardianID == id }
    }

    // MARK: - The roster

    /// One entry per distinct child, named by whoever wrote most recently.
    ///
    /// A rename is therefore last-writer-wins, which is the one place in this design that
    /// rule is still the right one: a name is cosmetic, both guardians see the same one
    /// within a sync, and the id it hangs off never moves.
    /// Newest name per guardian id, so renaming yourself renames you everywhere rather
    /// than adding a second person.
    private static func guardians(from files: [ShelfFile]) -> [Profiles.Guardian] {
        var newest: [UUID: ShelfFile] = [:]
        for file in files {
            if let standing = newest[file.guardianID], standing.writtenAt >= file.writtenAt { continue }
            newest[file.guardianID] = file
        }
        return newest.values
            .map { Profiles.Guardian(id: $0.guardianID, name: $0.guardianName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

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

    // MARK: - Devices

    /// This install's own id, made once and kept. Not derived from anything the system
    /// offers: `identifierForVendor` changes when the last app from a vendor is deleted,
    /// and a device that came back with a new id would appear as a second device.
    private var deviceID: UUID {
        let key = "shelf.device.id"
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) {
            return id
        }
        let made = UUID()
        UserDefaults.standard.set(made.uuidString, forKey: key)
        return made
    }

    /// The name this device shows in the family list, until somebody renames it.
    var suggestedDeviceName: String {
        let kind = DeviceRecord.Kind.current.noun
        guard let person = personName else { return kind.capitalized }
        return "\(person)'s \(kind)"
    }

    private var personName: String?
    private var personID: UUID?

    /// Say that this device exists, who is holding it, and how far along it is.
    ///
    /// Called on every refresh rather than once at setup: the interesting fields are
    /// `lastSeen` and the gap between `approved` and `downloaded`, and a record written
    /// once would be a row that goes stale and lies.
    @discardableResult
    func announce(
        name: String? = nil,
        person: (id: UUID, name: String)?,
        isMinor: Bool,
        approved: Int = 0,
        downloaded: Int = 0
    ) async -> Bool {
        guard let folder else { return false }
        personID = person?.id
        personName = person?.name

        let id = deviceID
        let existing = devices.first { $0.deviceID == id }
        let record = DeviceRecord(
            deviceID: id,
            // A name already chosen wins over a freshly suggested one, so renaming a
            // device is not undone by the next refresh.
            name: name ?? existing?.name ?? suggestedDeviceName,
            kind: .current,
            personID: person?.id,
            personName: person?.name,
            isMinor: isMinor,
            lastSeen: Date(),
            approved: approved,
            downloaded: downloaded
        )

        let wrote = await Task.detached { Self.write(record, in: folder) }.value
        guard wrote else { return false }
        devices.removeAll { $0.deviceID == id }
        devices.append(record)
        devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return true
    }

    /// Put this guardian on the family list without waiting for their first approval.
    ///
    /// Writes an empty shelf for each child they do not already have one for. That is
    /// what makes "the other parent appears once they are set up" true — until a guardian
    /// has written *something*, there is nothing in the folder with their name on it and
    /// no honest way to know they exist.
    func announce(guardian: Profiles.Guardian) async {
        guard folder != nil else { return }
        for minor in roster where !files.contains(where: {
            $0.minorID == minor.id && $0.guardianID == guardian.id
        }) {
            await record([], for: minor, as: guardian, evenIfEmpty: true)
        }
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
            for url in names where url.pathExtension.lowercased() == "json"
                && !url.lastPathComponent.hasPrefix(DeviceRecord.prefix)
                && !url.lastPathComponent.hasPrefix(PeopleFile.prefix) {
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

    private nonisolated static func readPeople(in folder: URL) -> [PeopleFile] {
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }

        guard let names = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [PeopleFile] = []
        for url in names where url.lastPathComponent.hasPrefix(PeopleFile.prefix) {
            guard materialise(url),
                  let data = try? Data(contentsOf: url),
                  let file = try? decoder.decode(PeopleFile.self, from: data)
            else { continue }
            found.append(file)
        }
        return found
    }

    private nonisolated static func write(_ file: PeopleFile, in folder: URL) -> Bool {
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }
        guard let data = try? encoder.encode(file) else { return false }
        let url = folder.appendingPathComponent(file.filename)
        var failure: NSError?
        var wrote = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &failure) { destination in
            wrote = (try? data.write(to: destination, options: .atomic)) != nil
        }
        return wrote && failure == nil
    }

    private nonisolated static func readDevices(in folder: URL) -> [DeviceRecord] {
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }

        guard let names = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [DeviceRecord] = []
        for url in names where url.lastPathComponent.hasPrefix(DeviceRecord.prefix) {
            guard materialise(url),
                  let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(DeviceRecord.self, from: data)
            else { continue }
            found.append(record)
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func write(_ record: DeviceRecord, in folder: URL) -> Bool {
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }
        guard let data = try? encoder.encode(record) else { return false }
        let url = folder.appendingPathComponent(record.filename)
        var failure: NSError?
        var wrote = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &failure) { destination in
            wrote = (try? data.write(to: destination, options: .atomic)) != nil
        }
        return wrote && failure == nil
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
