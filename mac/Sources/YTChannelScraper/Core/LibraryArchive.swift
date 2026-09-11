import Foundation

/// Everything you have kept, in one file you can carry to another Mac.
///
/// The library is per-account and local — `~/Library/Application Support` on one machine,
/// belonging to one login — which is right for what it is but leaves no way across. This
/// is that way: one document holding both lists, written whole and merged on the far side.
///
/// Deliberately readable JSON rather than an opaque bundle. It is a few hundred entries at
/// most, the shape is the same as what the app already writes to disk, and a transfer
/// format you can open in a text editor is one you can still rescue something from in five
/// years when this app is gone.
struct LibraryArchive: Codable, Sendable {
    /// Bumped only when an older app could no longer read it. Anything it does not
    /// recognise is a file from a newer version, and it says so rather than guessing.
    static let currentFormat = 1
    static let fileExtension = "ytcslibrary"

    var format: Int = LibraryArchive.currentFormat
    var app: String = Paths.appName
    var exportedAt: Date = Date()
    var channels: [Channel]
    var videos: [Video]

    /// Dates go out as ISO-8601 so the file reads as text rather than as seconds since a
    /// reference date only Foundation knows.
    ///
    /// With fractional seconds, because `.iso8601` rounds to the whole second and a
    /// library exported and read straight back would then differ from itself. Nothing
    /// downstream depends on the millisecond, but a transfer format that does not return
    /// what it was given is a format with a question mark over it.
    ///
    /// Millisecond, not exact: a `Date` carries finer precision than that, so a timestamp
    /// comes back up to half a millisecond off. Nothing here compares dates for equality —
    /// channels match on id, and the merge only ever takes the earlier or the later of
    /// two — so that is precision spent where it is readable rather than where it is not.
    /// Built per call rather than held as shared statics: `ISO8601DateFormatter` is a
    /// class with mutable options and is not `Sendable`, and this runs twice per export —
    /// nowhere near often enough to be worth reaching for an isolated cache.
    static func coders() -> (JSONEncoder, JSONDecoder) {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(precise.string(from: date))
        }

        let decoder = JSONDecoder()
        // Either spelling is read, so a file from any version of this format still opens.
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = precise.date(from: text) ?? whole.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Not a date: \(text)"
                ))
            }
            return date
        }
        return (encoder, decoder)
    }

    static func read(from url: URL) throws -> LibraryArchive {
        let (_, decoder) = coders()
        let archive: LibraryArchive
        do {
            archive = try decoder.decode(LibraryArchive.self, from: Data(contentsOf: url))
        } catch {
            throw Failure.unreadable
        }
        guard archive.format <= currentFormat else { throw Failure.tooNew }
        return archive
    }

    func write(to url: URL) throws {
        let (encoder, _) = Self.coders()
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// What to call the file. Dated, because the point of one is that it is a snapshot.
    static var suggestedFilename: String {
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "\(Paths.appName) Library \(stamp).\(fileExtension)"
    }

    enum Failure: LocalizedError {
        case unreadable
        case tooNew

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "That file is not a \(Paths.appName) library."
            case .tooNew:
                "That library was made by a newer version of the app."
            }
        }
    }
}
