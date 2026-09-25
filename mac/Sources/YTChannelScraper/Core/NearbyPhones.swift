import Foundation

/// The phones this Mac can reach right now, over the cable or the local network, and a
/// way to make each one sync.
///
/// "Sync" means opening the app on the phone. The phone does its own fetching — it reads
/// the family folder and downloads whatever has been approved, over its own connection —
/// but it only does that when the app comes to the front. Somebody dropping a video on a
/// child here should not have to go and find the child's phone to see it arrive, so the
/// Mac opens the app for them.
///
/// Watched only while something on screen asks: `devicectl` takes a second or so per
/// listing, which is nothing every fifteen seconds and a waste when the board is hidden.
@MainActor
@Observable
final class NearbyPhones {
    private(set) var phones: [PhoneDeployer.Phone] = []
    /// Whether this Mac can talk to phones at all — false without Xcode.
    private(set) var isAvailable = true
    /// Per phone, what the last sync did.
    private(set) var status: [String: Status] = [:]
    /// Which child each phone was set up for. Mirrored here from `PhoneDeployer` so the
    /// board redraws the moment a setup finishes — `UserDefaults` itself is not observed.
    private(set) var owners: [String: UUID] = PhoneDeployer.owners()

    func owner(of phone: PhoneDeployer.Phone) -> UUID? { owners[phone.id] }

    // MARK: - Retiring a child's phone

    /// Phones whose child has been removed, still waiting for the app to be deleted
    /// because they were out of reach at the time. Kept across launches: the point is
    /// that the cleanup happens whenever the phone next turns up, not only if it happened
    /// to be on the cable that minute.
    private(set) var pendingRemoval: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: NearbyPhones.pendingKey) ?? [])
    private static let pendingKey = "phoneSetup.pendingRemoval"

    /// The phones this Mac set up for a child, by UDID — for saying which will be cleared.
    func phoneIDs(ownedBy childID: UUID) -> [String] {
        owners.filter { $0.value == childID }.map(\.key)
    }

    /// A child has been removed: take the app off every phone this Mac set up for them.
    /// Now if the phone is in reach, otherwise the next time it is.
    func retire(childID: UUID) async {
        let targets = phoneIDs(ownedBy: childID)
        guard !targets.isEmpty else { return }
        pendingRemoval.formUnion(targets)
        savePending()
        await removePending()
    }

    private func removePending() async {
        for phone in phones where pendingRemoval.contains(phone.id) {
            status[phone.id] = .syncing
            do {
                try await PhoneDeployer.uninstall(bundleID: Self.bundleID, from: phone)
                pendingRemoval.remove(phone.id)
                PhoneDeployer.forget(phone.id)
                owners = PhoneDeployer.owners()
                status[phone.id] = nil
            } catch {
                // Stays pending; a locked phone, most likely. Tried again next time round.
                status[phone.id] = .failed(error.localizedDescription)
            }
        }
        savePending()
    }

    private func savePending() {
        UserDefaults.standard.set(Array(pendingRemoval), forKey: Self.pendingKey)
    }

    func remember(_ phone: PhoneDeployer.Phone, isFor minor: Profiles.Minor) {
        PhoneDeployer.remember(phone, isFor: minor)
        owners = PhoneDeployer.owners()
    }

    enum Status: Equatable {
        case syncing
        case synced(Date)
        case failed(String)
    }

    private var watchers = 0
    private var loop: Task<Void, Never>?

    /// The iPhone app answers to the same bundle id as this one — the two share an iCloud
    /// container, which needs it — so that is what gets opened.
    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.d4vid4nderson.ytchannelscraper"
    }

    func startWatching() {
        watchers += 1
        guard loop == nil else { return }
        loop = Task { [weak self] in
            if await PhoneDeployer.isAvailable() == false {
                self?.isAvailable = false
                return
            }
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        loop?.cancel()
        loop = nil
    }

    func refresh() async {
        guard let found = try? await PhoneDeployer.phones() else { return }
        // Only phones that can be reached now. The pairing list keeps every phone this
        // Mac has ever trusted, and a Sync button for one that is switched off in a
        // drawer can only fail.
        phones = found.filter(\.isReachable)
        if !pendingRemoval.isEmpty { await removePending() }
    }

    /// Make a phone current with the family, whichever way it can be reached.
    ///
    /// 1. Bring back what the phone last said about itself and put it in the shared
    ///    folder, so the board shows it — a phone reading a delivered copy has no other
    ///    way to be seen.
    /// 2. If the phone is holding an old identity for the child this Mac set it up for,
    ///    say the two are the same person. Removing and re-adding a child mints a new id,
    ///    and a locked phone will not move to it on its own.
    /// 3. Deliver the family folder, then open the app so it reads it and starts
    ///    downloading.
    /// 4. A little later, bring back the phone's fresh report.
    func sync(_ phone: PhoneDeployer.Phone, shelf: ShelfStore, guardian: Profiles.Guardian?) async {
        status[phone.id] = .syncing
        let bundleID = Self.bundleID
        do {
            await collect(from: phone, into: shelf, guardian: guardian)
            if let folder = shelf.folder, !shelf.isDeliveredCopy {
                try await PhoneDeployer.deliver(familyFolder: folder, bundleID: bundleID, to: phone)
            }
            try await PhoneDeployer.open(bundleID: bundleID, on: phone)
            status[phone.id] = .synced(Date())
        } catch {
            status[phone.id] = .failed(error.localizedDescription)
            return
        }
        // Long enough for the app to read, reconcile and write its report.
        try? await Task.sleep(for: .seconds(10))
        await collect(from: phone, into: shelf, guardian: guardian)
    }

    private func collect(from phone: PhoneDeployer.Phone, into shelf: ShelfStore,
                         guardian: Profiles.Guardian?) async {
        let reports = await PhoneDeployer.collectReports(bundleID: Self.bundleID, from: phone)
        var relayed = false
        for data in reports {
            guard let record = await shelf.relay(deviceRecord: data) else { continue }
            relayed = true
            if let guardian, let owner = owner(of: phone), record.isMinor,
               let holding = record.personID, holding != owner,
               shelf.roster.contains(where: { $0.id == owner }),
               !shelf.family(of: owner).contains(holding) {
                await shelf.attach(holding, to: owner, as: guardian)
            }
        }
        if relayed { await shelf.refresh() }
    }

    /// Sync every phone set up for this child that can be reached — called after
    /// something is sent to them, so it lands without anybody touching the phone.
    func sync(childID: UUID, shelf: ShelfStore, guardian: Profiles.Guardian?) async {
        for phone in phones where owner(of: phone) == childID {
            await sync(phone, shelf: shelf, guardian: guardian)
        }
    }
}
