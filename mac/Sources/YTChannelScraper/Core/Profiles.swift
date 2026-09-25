import CryptoKit
import Foundation
import LocalAuthentication
import os

/// Who is holding the phone: the parent who curates, or the minor who watches.
///
/// There are no accounts in the usual sense — no server, no sign-in, nothing to host.
/// The app is entirely local and the library is two JSON files, so a "profile" here is
/// one bit of state plus a PIN that guards flipping it. That bit decides which tabs
/// exist: a parent sees Search and can download; a minor sees the shelf the parent
/// filled and can play from it.
///
/// ## Where the two values live, and why
///
/// Both in the **Keychain**, not `UserDefaults`. Application Support and the defaults
/// database both go when the app is deleted, so a minor who deletes and reinstalls
/// would come back to an unlocked app with a Search tab. Keychain items survive that.
/// The library does not survive it, so the reinstall trick gets you a locked, empty app
/// — which is the right way for this to fail.
///
/// `ThisDeviceOnly` on both: the mode a minor's phone is in is not something to sync to
/// the parent's phone over iCloud Keychain, or to restore onto a different device.
///
/// ## What this is and is not
///
/// It is a lock on a door, not a vault. Four digits is ten thousand guesses, and the
/// hash below does not change that — `attempts` is what makes guessing cost real time.
/// The honest security boundary is the device passcode and, if you want a hard one,
/// iOS's own Screen Time or Guided Access on top of this. What this buys is that the
/// minor cannot *casually* wander into a search field, which is the actual problem.
@MainActor
@Observable
final class Profiles {
    /// One of the adults who curates. The id is what a shelf file is named after and
    /// never changes; the name is display only, so renaming yourself does not orphan
    /// everything you have already approved.
    struct Guardian: Codable, Hashable, Sendable {
        let id: UUID
        var name: String
    }

    /// One of the children being curated for. Created by a guardian, and identified the
    /// same way for the same reason — the shelf is keyed on the id, not the name.
    struct Minor: Codable, Hashable, Sendable {
        let id: UUID
        var name: String
    }

    enum Mode: Codable, Hashable, Sendable {
        case guardian
        /// Locked. The associated value is which child this device belongs to, which is
        /// what tells the reconciler whose shelf to pull.
        ///
        /// Nil is reachable exactly once, by upgrading an install from before this
        /// existed: the old keychain item recorded *that* the device was locked and not
        /// for whom, and inventing an answer would hand a child somebody else's shelf.
        /// The device stays locked and asks a guardian to say which child it is.
        case minor(Minor?)
    }

    private(set) var mode: Mode
    /// Who this device's owner is, when it is a guardian's device. Held separately from
    /// `mode` on purpose: locking a phone must not erase the identity that has been
    /// signing this guardian's approvals, or unlocking would come back as a stranger and
    /// every decision they had made would stop being attributable to them.
    private(set) var guardian: Guardian?
    /// Whether a PIN has ever been set. Without one there is nothing to flip back from,
    /// so Minor Mode cannot be turned on until it is.
    private(set) var hasPIN: Bool
    /// Opt-in, and off by default — see `useFaceID`'s setter.
    private(set) var useFaceID: Bool

    var isMinor: Bool { if case .minor = mode { true } else { false } }
    var isParent: Bool { !isMinor }

    /// Which child this device is locked to, if it is locked and has been told. Nil on a
    /// guardian's phone, and nil on a device carried over from before identities existed
    /// — `needsMinorAssignment` distinguishes the two.
    var minor: Minor? { if case .minor(let minor) = mode { minor } else { nil } }

    /// Locked, but with no child attached: the migrated case. The minor's screens have
    /// nothing to draw and the app should say so rather than show an empty shelf that
    /// looks like a sync failure.
    var needsMinorAssignment: Bool { if case .minor(nil) = mode { true } else { false } }

    /// The child this device was last locked to, kept through an unlock.
    ///
    /// A parent unlocks a child's phone to manage it and then needs to hand it back.
    /// Without this, locking again meant picking the child from the family list — which
    /// a phone with no adult identity of its own, or no folder connected yet, cannot
    /// show — so there was no way back into Minor Mode at all.
    var lastMinor: Minor? { Keychain.decode(Minor.self, for: Key.lastMinor) }

    /// Lock again as whoever this phone belonged to last.
    @discardableResult
    func relock() -> Bool {
        guard let lastMinor else { return false }
        return lock(as: lastMinor)
    }

    init() {
        hasPIN = Keychain.data(for: Key.pin) != nil
        useFaceID = Keychain.string(for: Key.faceID) == "1"
        guardian = Keychain.decode(Guardian.self, for: Key.guardian)
        mode = Self.storedMode()

        // A mode with no PIN behind it cannot be escaped, which would brick the app for
        // the parent too. It should not be reachable — `lock(as:)` requires a PIN — but
        // if a keychain item ever went missing on its own, this is the recovery.
        if isMinor && !hasPIN {
            Log.profiles.error("minor mode with no PIN stored; unlocking")
            mode = .guardian
            persistMode(.guardian)
        }
    }

    /// Read the mode, preferring the current format and falling back to the one that
    /// predates guardians.
    ///
    /// Fail closed, twice over: an absent value means guardian only because a fresh
    /// install genuinely is one, and a v1 value of "minor" becomes `.minor(nil)` rather
    /// than `.guardian`. A migration that unlocked the phone would be a migration that
    /// handed a child the Search tab, silently, on upgrade.
    private static func storedMode() -> Mode {
        if let mode = Keychain.decode(Mode.self, for: Key.mode) { return mode }
        switch Keychain.string(for: Key.modeV1) {
        case "minor":
            Log.profiles.notice("migrating v1 minor mode; awaiting assignment")
            return .minor(nil)
        default:
            return .guardian
        }
    }

    // MARK: - Identity

    /// Become a guardian identity that already exists, rather than minting a new one.
    ///
    /// This is what makes "add Jill on my Mac, then Jill's phone becomes Jill" work. The
    /// id has to be the one already in the shared folder — a second id with the same name
    /// would be a second person, and every approval either of them made would be filed
    /// under a different author.
    @discardableResult
    func adopt(_ guardian: Guardian) -> Bool {
        guard Keychain.encode(guardian, for: Key.guardian) else { return false }
        self.guardian = guardian
        return true
    }

    /// Name this device's guardian, keeping the id they already have. Called at setup,
    /// and again from a rename.
    @discardableResult
    func setGuardianName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let updated = Guardian(id: guardian?.id ?? UUID(), name: trimmed)
        guard Keychain.encode(updated, for: Key.guardian) else { return false }
        guardian = updated
        return true
    }

    // MARK: - Setting the PIN

    /// Store a new PIN. Called at setup, and again from Change PIN — which asks for the
    /// old one first, so there is nothing to check here.
    ///
    /// False means the Keychain refused the write, and the app has no PIN. Rare, but the
    /// screen that asked has to say so rather than move on: the whole feature rests on
    /// this one value being on disk.
    @discardableResult
    func setPIN(_ pin: String) -> Bool {
        guard Keychain.set(Self.pinRecord(for: pin), for: Key.pin) else {
            hasPIN = Keychain.data(for: Key.pin) != nil
            return false
        }
        hasPIN = true
        clearAttempts()
        return true
    }

    /// Salt then hash: what the Keychain holds, and what `ChildSetup` carries so a Mac can
    /// set a phone's PIN without the digits ever leaving the Mac.
    nonisolated static func pinRecord(for pin: String) -> Data {
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        return salt + hash(pin, salt: salt)
    }

    nonisolated static let pinRecordLength = 16 + 32

    func matches(_ pin: String) -> Bool {
        guard let stored = Keychain.data(for: Key.pin), stored.count == Self.pinRecordLength
        else { return false }
        let expected = Self.hash(pin, salt: stored.prefix(16))
        // Every byte, every time. `==` and `elementsEqual` both stop at the first
        // difference, which leaks how much of a guess was right through how long the
        // comparison took. Not a threat model anyone is realistically running against a
        // phone in a kitchen — but the whole loop is four lines, so there is no reason
        // to be the version that leaks.
        var difference: UInt8 = 0
        for (mine, theirs) in zip(expected, stored.dropFirst(16)) {
            difference |= mine ^ theirs
        }
        return difference == 0
    }

    /// Salted SHA-256. Ten thousand possible inputs means this is not what stops a
    /// determined attacker with the keychain item in hand — `attempts` and the device's
    /// own passcode are. It stops the PIN being readable in a backup or a dump, which is
    /// worth the four lines it costs.
    private nonisolated static func hash(_ pin: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }

    // MARK: - Switching

    /// Hand the phone to a specific child. Requires a PIN to already exist, because the
    /// mode is only meaningful if there is a way back out of it.
    ///
    /// Which child is not a detail: it selects the shelf this device will pull and the
    /// files it will keep, so it is taken here rather than guessed later.
    @discardableResult
    func lock(as minor: Minor) -> Bool {
        guard hasPIN else { return false }
        // Written before the in-memory switch, not after: a mode that only exists in
        // this process is one relaunch away from being gone, and a parent who has
        // handed the phone over will not be there to see it come back.
        guard persistMode(.minor(minor)) else { return false }
        mode = .minor(minor)
        Keychain.encode(minor, for: Key.lastMinor)
        return true
    }

    /// What applying a setup from the Mac did.
    enum SetupOutcome: Equatable {
        /// Locked as that child. `keptPIN` when the phone already had a PIN, which is
        /// left alone and is still the one that unlocks it.
        case locked(keptPIN: Bool)
        /// Already that child's phone; nothing changed.
        case alreadyThisChild
        /// Already another child's phone. Changing whose it is needs the PIN, on the
        /// phone, so a file cannot do it.
        case refused
        case failed
    }

    /// Become a child's phone because the Mac said so.
    ///
    /// Only ever locks, which is why it needs no PIN: a phone that is still a parent's is
    /// already fully open to whoever is holding it, so locking it takes nothing away from
    /// them. What it will not do is the two things a stray file could abuse — replace a
    /// PIN that exists, or move a phone that is already locked to a different child.
    ///
    /// The adult identity is dropped. A child's phone that had been set up as an adult
    /// first would otherwise keep announcing that adult whenever a parent unlocked it,
    /// and the child would reappear in the Admins list.
    @discardableResult
    func apply(_ setup: ChildSetup) -> SetupOutcome {
        if case .minor(let current?) = mode {
            return current.id == setup.minor.id ? .alreadyThisChild : .refused
        }
        let keptPIN = hasPIN
        if !keptPIN {
            guard setup.pinRecord.count == Self.pinRecordLength,
                  Keychain.set(setup.pinRecord, for: Key.pin)
            else { return .failed }
            hasPIN = true
            clearAttempts()
        }
        guard persistMode(.minor(setup.minor)) else { return .failed }
        mode = .minor(setup.minor)
        Keychain.encode(setup.minor, for: Key.lastMinor)
        Keychain.remove(Key.guardian)
        guardian = nil
        Log.profiles.notice("set up from the Mac as a child's phone")
        return .locked(keptPIN: keptPIN)
    }

    /// Attach a child to a device that was locked before identities existed. Behind the
    /// PIN, because it decides what the device is allowed to show.
    @discardableResult
    func assign(_ minor: Minor, pin: String) -> Bool {
        guard needsMinorAssignment, matches(pin) else { return false }
        guard persistMode(.minor(minor)) else { return false }
        mode = .minor(minor)
        clearAttempts()
        return true
    }

    /// Back to the parent, if the PIN is right. Wrong answers are counted and slowed.
    func unlock(with pin: String) -> Bool {
        guard penalty == nil else { return false }
        guard matches(pin) else {
            recordFailure()
            return false
        }
        mode = .guardian
        persistMode(.guardian)
        clearAttempts()
        return true
    }

    /// Back to the parent on a successful Face ID check. Separate from `unlock(with:)`
    /// because the system did the authenticating and there is no PIN to compare.
    func unlockWithBiometrics() async -> Bool {
        guard useFaceID, penalty == nil else { return false }
        let context = LAContext()
        context.localizedFallbackTitle = ""      // the PIN pad is already on screen
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        else { return false }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Minor Mode")
            guard ok else { return false }
            mode = .guardian
            persistMode(.guardian)
            clearAttempts()
            return true
        } catch {
            return false
        }
    }

    /// Whether the device has a face or a finger enrolled at all, and what to call it.
    /// Nil when there is nothing to offer — a phone with no biometrics, or one where the
    /// user has turned it off for this app.
    var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        else { return nil }
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return nil
        }
    }

    /// Off unless explicitly turned on, and the settings screen says why in as many
    /// words: this is most likely the *minor's* phone, so the face enrolled on it is
    /// most likely their face. Face ID is a convenience for a parent locking
    /// their own device, and a hole in anybody else's.
    func setUseFaceID(_ on: Bool) {
        useFaceID = on
        Keychain.set(Data((on ? "1" : "0").utf8), for: Key.faceID)
    }

    /// Turn the whole thing off: forget the PIN and go back to an app with no modes.
    /// Only reachable from the parent's settings, which is already behind the PIN.
    func forgetPIN() {
        Keychain.remove(Key.pin)
        Keychain.remove(Key.faceID)
        hasPIN = false
        useFaceID = false
        mode = .guardian
        persistMode(.guardian)
        clearAttempts()
    }

    /// Takes the mode rather than reading `self.mode`, so `lock()` can write first and
    /// only adopt the new mode once the write has landed.
    @discardableResult
    private func persistMode(_ mode: Mode) -> Bool {
        // The v1 item is cleared rather than left behind, so a downgrade cannot find a
        // stale "minor" and lock a phone whose current mode says otherwise.
        Keychain.remove(Key.modeV1)
        return Keychain.encode(mode, for: Key.mode)
    }

    // MARK: - Slowing down guesses

    /// How many wrong PINs in a row. Four digits is a space a patient teenager will walk
    /// through in an afternoon, so the answer is not a better hash — it is to make the
    /// afternoon into a week.
    private(set) var failures = 0
    /// When guessing is allowed again, if it is not allowed now.
    private(set) var lockedUntil: Date?

    /// Seconds left before another guess is accepted, or nil if one is accepted now.
    var penalty: TimeInterval? {
        guard let until = lockedUntil else { return nil }
        let remaining = until.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    private func recordFailure() {
        failures += 1
        // Free for the first four — a mistyped digit should not cost anything. Then
        // 30s, 1m, 2m, 4m… capped at an hour.
        guard failures >= 5 else { return }
        let seconds = min(30 * pow(2, Double(failures - 5)), 3600)
        lockedUntil = Date().addingTimeInterval(seconds)
    }

    private func clearAttempts() {
        failures = 0
        lockedUntil = nil
    }

    // MARK: - Keys

    private enum Key {
        static let pin = "profile.pin"
        /// The pre-guardian mode item: a bare "parent" or "minor". Read once on upgrade
        /// by `storedMode()` and deleted on the next write.
        static let modeV1 = "profile.mode"
        static let mode = "profile.mode.v2"
        static let guardian = "profile.guardian"
        static let faceID = "profile.faceID"
        static let lastMinor = "profile.lastMinor"
    }
}

/// The three keychain calls this app needs, and no more.
///
/// A generic-password item per key, scoped to this app's service string and readable
/// only while the device is unlocked and only on this device.
private enum Keychain {
    private static let service = "com.d4vid4nderson.ytchannelscraper.profiles"

    static func data(for key: String) -> Data? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
        else { return nil }
        return result as? Data
    }

    static func string(for key: String) -> String? {
        data(for: key).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// A `Codable` value, for the two items that outgrew being a string. A value that
    /// fails to decode is treated as absent — callers already handle nil, and every one
    /// of them fails closed when they get it.
    static func decode<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let data = data(for: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Log.profiles.error("keychain item \(key, privacy: .public) did not decode: \(error)")
            return nil
        }
    }

    @discardableResult
    static func encode(_ value: some Encodable, for key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return set(data, for: key)
    }

    /// Returns whether the value is actually on disk. Callers have to care: a PIN that
    /// was not stored is a Minor Mode that unlocks itself at the next launch, and telling
    /// the parent it is set would be worse than not offering it.
    @discardableResult
    static func set(_ value: Data, for key: String) -> Bool {
        // Update first, because SecItemAdd on an existing item is errSecDuplicateItem
        // rather than an overwrite.
        let updated = SecItemUpdate(base(key) as CFDictionary,
                                    [kSecValueData as String: value] as CFDictionary)
        if updated == errSecSuccess { return true }

        var item = base(key)
        item[kSecValueData as String] = value
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else {
            Log.profiles.error("keychain write failed for \(key, privacy: .public): \(added)")
            return false
        }
        return true
    }

    static func remove(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
    }

    private static func base(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

extension Log {
    /// Which profile the app is in, and why it changed.
    static let profiles = Logger(subsystem: "com.d4vid4nderson.ytchannelscraper",
                                 category: "profiles")
}
