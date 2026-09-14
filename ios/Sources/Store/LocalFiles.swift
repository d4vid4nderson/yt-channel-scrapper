import Foundation

/// One finished file sitting in Documents.
///
/// Nothing persists this. The directory *is* the record — `Paths.filename` writes the
/// title and the video id into the name, and reading them back out costs a directory
/// listing. That matters more than it sounds: `Downloads` holds its jobs in memory, so
/// before this type there was no way to reach yesterday's download at all, and the files
/// are deliberately visible in Files.app where the user can rename, move or delete them
/// behind the app's back. A scan cannot disagree with the disk; an index would.
struct LocalFile: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case video, audio }

    let url: URL
    let title: String
    /// The YouTube id, recovered from the `Title [id].ext` name. Nil for anything the
    /// user put in the folder themselves, which is allowed to be here and plays fine —
    /// it just has no poster to go with it.
    let videoID: String?
    let kind: Kind
    let bytes: Int64
    let added: Date

    var id: String { url.path }

    var artwork: URL? {
        videoID.flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/mqdefault.jpg") }
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var subtitle: String {
        let when = added.formatted(date: .abbreviated, time: .omitted)
        return "\(sizeText)  ·  \(when)"
    }
}

/// What is on the phone right now.
@MainActor
@Observable
final class LocalFiles {
    private(set) var files: [LocalFile] = []

    /// What `Muxer` writes, plus the handful of things a user might reasonably drop into
    /// the folder over Files.app and expect to play.
    private static let playable: Set<String> = ["mp4", "m4v", "mov", "m4a", "mp3", "aac", "wav"]

    var isEmpty: Bool { files.isEmpty }

    /// Re-read the directory. Cheap enough to call on every appearance, which is what
    /// keeps the list honest after a deletion made in Files.app.
    func reload() {
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .isRegularFileKey]
        let found = (try? FileManager.default.contentsOfDirectory(
            at: Paths.downloads,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles])) ?? []

        files = found
            .compactMap { Self.describe($0, keys: Set(keys)) }
            .sorted { $0.added > $1.added }
    }

    func delete(_ file: LocalFile) {
        do {
            try FileManager.default.removeItem(at: file.url)
            files.removeAll { $0.id == file.id }
        } catch {
            Log.transfer.error("delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reading one entry

    private static func describe(_ url: URL, keys: Set<URLResourceKey>) -> LocalFile? {
        guard playable.contains(url.pathExtension.lowercased()) else { return nil }
        let values = try? url.resourceValues(forKeys: keys)
        guard values?.isRegularFile != false else { return nil }

        let parsed = parse(url.lastPathComponent)
        let audio = ["m4a", "mp3", "aac", "wav"].contains(url.pathExtension.lowercased())
        return LocalFile(
            url: url,
            title: parsed.title,
            videoID: parsed.id,
            kind: audio ? .audio : .video,
            bytes: Int64(values?.fileSize ?? 0),
            added: values?.creationDate ?? .distantPast
        )
    }

    /// Undo `Paths.filename`, and `Paths.available` on top of it: `Title [dQw4w9WgXcQ]
    /// (2).mp4` has to give back the title and the id, not one long name.
    ///
    /// The id is only accepted when it looks like one — eleven characters of YouTube's
    /// alphabet. A title that genuinely ends in brackets keeps them rather than having a
    /// chunk of itself silently read as an id.
    static func parse(_ filename: String) -> (title: String, id: String?) {
        var base = (filename as NSString).deletingPathExtension

        // The " (2)" a name collision appends, if it is there.
        if base.hasSuffix(")"), let open = base.range(of: " (", options: .backwards) {
            let suffix = base[open.upperBound..<base.index(before: base.endIndex)]
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                base = String(base[base.startIndex..<open.lowerBound])
            }
        }

        guard base.hasSuffix("]"), let open = base.range(of: " [", options: .backwards)
        else { return (base, nil) }

        let id = String(base[open.upperBound..<base.index(before: base.endIndex)])
        let alphabet = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard id.count == 11, id.allSatisfy(alphabet.contains)
        else { return (base, nil) }

        let title = String(base[base.startIndex..<open.lowerBound])
        return (title.isEmpty ? id : title, id)
    }
}
