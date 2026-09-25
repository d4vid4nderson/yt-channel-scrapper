import Foundation

/// A child's phone, set up from the Mac over the cable.
///
/// Before this, a phone became a child's by being set up *as an adult first*: the Family
/// screen asks you to name yourself before it will connect to anything, so the child
/// ended up in the Admins list and had to be moved out of it by hand. The Mac already
/// knows who the child is — it created them — so it hands the phone that answer directly
/// and the phone never has an adult identity at all.
///
/// Shared between the two apps because both halves have to agree on the bytes: the Mac
/// writes it, the phone reads it.
///
/// ## What it can and cannot do
///
/// It can only ever *lock* a phone. `Profiles.apply(_:)` refuses it on a phone that is
/// already a child's, and never replaces a PIN that is already set. That matters because
/// the file arrives through the app's Documents folder, which Finder can also write to:
/// anybody able to drop a file there could otherwise use one to reset the PIN and let
/// themselves out.
///
/// The PIN travels as the same salted hash `Profiles` keeps in the Keychain, never as
/// the digits.
struct ChildSetup: Codable, Sendable, Equatable {
    /// Where the Mac puts it, inside the app's Documents folder. Hidden, so `LocalFiles`
    /// skips it and Files.app does not show it.
    static let filename = ".ytcs-child-setup.json"
    /// The launch argument that carries the same thing, for when the file copy is not
    /// allowed. Followed by the setup as base64 JSON.
    static let argument = "-ytcsChildSetup"

    var version = 1
    let minor: Profiles.Minor
    /// Salt followed by SHA-256, exactly what `Profiles` stores.
    let pinRecord: Data
    /// Shown on the phone so the person holding it knows which folder to pick.
    let folderName: String?
    let createdAt: Date

    init(minor: Profiles.Minor, pin: String, folderName: String?) {
        self.minor = minor
        self.pinRecord = Profiles.pinRecord(for: pin)
        self.folderName = folderName
        self.createdAt = Date()
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) -> ChildSetup? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let setup = try? decoder.decode(ChildSetup.self, from: data),
              setup.version == 1,
              setup.pinRecord.count == Profiles.pinRecordLength,
              !setup.minor.name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return setup
    }

    /// The setup carried on the command line, if this launch was given one.
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> ChildSetup? {
        guard let flag = arguments.firstIndex(of: argument),
              arguments.indices.contains(flag + 1),
              let data = Data(base64Encoded: arguments[flag + 1])
        else { return nil }
        return decode(data)
    }
}
