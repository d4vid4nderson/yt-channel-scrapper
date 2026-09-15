import Foundation
import os

/// Keeps the library in iCloud, so deleting the app is no longer the same as losing it —
/// and so the Mac and the phone show the same shelf.
///
/// Compiled into **both** apps, like `LibraryArchive` beside it. They share a bundle
/// identifier and a team, so `$(TeamIdentifierPrefix)$(CFBundleIdentifier)` resolves to
/// the same key-value container on each and neither has to know the other exists.
///
/// The two JSON files live in Application Support, which iOS deletes along with the app.
/// That is correct behaviour and not something an app can opt out of — so the copy that
/// survives has to live somewhere iOS does not own. This is that copy, and the same copy
/// is what the Mac reads.
///
/// ## Why the key-value store rather than CloudKit
///
/// The whole library is a few kilobytes: eight channels and two videos encode to about
/// 3KB, and a 500-channel Takeout import would still be well under 200KB against a 1MB
/// ceiling. CloudKit would be the right answer for something that could outgrow that, and
/// the wrong one here — a container, a schema, a subscription and a conflict policy for
/// data that fits in a single value.
///
/// ## The conflict rule, stated plainly
///
/// **Last writer wins, on the whole archive.** Each snapshot carries the time it was
/// written; a device adopts the remote one only when it is newer than what it last wrote.
///
/// The alternative — merging the two sets — was rejected on purpose. A union can never
/// represent a deletion, so removing a channel on one device would see it reappear from
/// the other's copy, forever, with no way to get rid of it. Last-writer-wins makes a
/// deletion a real deletion. The cost is that edits made on two devices between syncs
/// can lose one side, which for one person curating a shelf is a trade worth making, and
/// for two people editing at once would not be.
///
/// ## The dangerous case, and the guard on it
///
/// A fresh install starts with an empty library. If it pushed that before reading iCloud
/// it would erase the very copy it exists to restore. So nothing is ever pushed until the
/// first read has come back — `hasSynced` is the entire safety mechanism, and every write
/// path goes through it.
@MainActor
@Observable
final class CloudMirror {
    /// What iCloud holds: the library, and when this copy was written.
    private struct Snapshot: Codable {
        var writtenAt: Date
        var archive: LibraryArchive
    }

    /// Versioned in the name so a future format change cannot be read by an older build
    /// as though it were the current one.
    private static let key = "library.snapshot.v1"

    /// The value store refuses anything over a megabyte, and silently — so this stops
    /// short of it rather than discovering the limit by hitting it.
    private static let sizeLimit = 900_000

    private let store = NSUbiquitousKeyValueStore.default

    /// False until the first read has returned. Nothing is written before that.
    private(set) var hasSynced = false

    /// What the user should be told, if anything. Nil when it is quietly working.
    private(set) var problem: String?

    /// When this device last wrote a snapshot. Held in `UserDefaults`, which is also
    /// deleted with the app — and that is the point: after a reinstall this is
    /// `distantPast`, so whatever is in iCloud is unambiguously newer and gets adopted.
    private var lastWrittenAt: Date {
        get { UserDefaults.standard.object(forKey: "library.writtenAt") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "library.writtenAt") }
    }

    /// Called when iCloud has a newer library than this device's. The library replaces
    /// its contents with what is handed over.
    var didReceive: ((LibraryArchive) -> Void)?

    private var pushTask: Task<Void, Never>?
    private let observer: Observer

    init() {
        let store = self.store
        observer = Observer(
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store,
                queue: nil
            ) { note in
                // The notification arrives on whatever queue iCloud felt like using.
                let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                Task { @MainActor in Self.current?.remoteChanged(reason: reason) }
            })
        Self.current = self
    }

    /// The one live mirror, so the notification block does not have to capture `self`
    /// before `self` exists. There is exactly one `Library`, and so exactly one of these.
    private static weak var current: CloudMirror?

    /// Owns the observer token and unregisters it when released.
    ///
    /// A `deinit` on `CloudMirror` itself cannot do this: under Swift 6 a deinit is
    /// nonisolated and may not touch main-actor state, which the token would be. Giving
    /// the token its own small non-isolated class sidesteps that without leaving a
    /// registration behind for the life of the process.
    private final class Observer: @unchecked Sendable {
        private let token: NSObjectProtocol
        init(_ token: NSObjectProtocol) { self.token = token }
        deinit { NotificationCenter.default.removeObserver(token) }
    }

    /// Read what iCloud has, once, at launch. Until this has run nothing is pushed.
    func start() {
        // Returns false when the user is not signed into iCloud, or has it switched off
        // for this app. Not an error — the app works exactly as before, just without a
        // copy anywhere else, and says so rather than implying it is protected.
        guard store.synchronize() else {
            problem = "Not signed into iCloud — the library is only on this phone."
            Log.cloud.notice("key-value store unavailable; local only")
            hasSynced = true
            return
        }
        adoptRemoteIfNewer()
        hasSynced = true
    }

    /// Mirror the library as it now stands. Cheap to call on every change: the actual
    /// write is coalesced into one a second later.
    func push(_ archive: LibraryArchive) {
        guard hasSynced else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.write(archive)
        }
    }

    // MARK: - The two directions

    private func write(_ archive: LibraryArchive) {
        let snapshot = Snapshot(writtenAt: Date(), archive: archive)
        let (encoder, _) = LibraryArchive.coders()
        guard let data = try? encoder.encode(snapshot) else { return }

        guard data.count <= Self.sizeLimit else {
            problem = "The library is too big for iCloud to hold (\(data.count / 1000)KB). "
                + "Export it by hand to keep a copy."
            Log.cloud.error("snapshot is \(data.count) bytes; over the limit, not written")
            return
        }

        store.set(data, forKey: Self.key)
        store.synchronize()
        lastWrittenAt = snapshot.writtenAt
        problem = nil
        Log.cloud.notice("mirrored \(archive.channels.count) channels, \(archive.videos.count) videos")
    }

    private func remoteChanged(reason: Int?) {
        // A quota failure is the one reason worth surfacing; the rest are routine.
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            problem = "iCloud storage is full, so the library is not being backed up."
            return
        }
        adoptRemoteIfNewer()
    }

    private func adoptRemoteIfNewer() {
        guard let data = store.data(forKey: Self.key) else { return }
        let (_, decoder) = LibraryArchive.coders()
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else {
            Log.cloud.error("could not read the snapshot in iCloud")
            return
        }
        guard snapshot.archive.format <= LibraryArchive.currentFormat else {
            problem = "iCloud holds a library from a newer version of the app."
            return
        }
        // Strictly newer: a snapshot this device wrote comes back as an external change
        // on its own devices, and adopting your own write is a pointless round trip.
        guard snapshot.writtenAt > lastWrittenAt else { return }

        Log.cloud.notice("adopting iCloud copy: \(snapshot.archive.channels.count) channels")
        lastWrittenAt = snapshot.writtenAt
        didReceive?(snapshot.archive)
    }
}

extension Log {
    /// What the iCloud mirror is doing, and why it is not doing it.
    static let cloud = Logger(subsystem: "com.d4vid4nderson.ytchannelscraper", category: "cloud")
}
