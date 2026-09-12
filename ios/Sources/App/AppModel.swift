import Foundation
import SwiftUI

/// What the app is doing, and what it knows.
///
/// A slimmer relative of the Mac app's `AppModel`. Most of what it dropped was window
/// management — three side drawers, a floating notch player, a Dock icon that follows
/// the system appearance — none of which mean anything on a phone. What is left is the
/// state the screens actually read.
@MainActor
@Observable
final class AppModel {
    // MARK: - Pieces

    let listing = Listing()
    let search = ChannelSearch()
    let library = Library()
    let downloads = Downloads()
    let playback = Playback()

    // MARK: - Input

    var urlText = ""
    var quality: Quality = .p1080
    /// Whether an m4a is wanted beside the video as well as the video itself.
    var alsoAudio = false
    var filterText = ""

    /// Which videos are ticked for a batch download. Empty means the toolbar acts on
    /// whatever row you tap instead.
    var picked: Set<String> = []
    var isSelecting = false

    /// The video the player sheet is showing, if any.
    var playing: Video?

    /// A message for the banner — an import result, an export path, a failure that is
    /// not attached to any one row.
    var banner: String?

    // MARK: - Derived

    /// What the search field is going to do when submitted: a URL or handle opens that
    /// channel directly, anything else searches for one.
    enum Intent { case open, find, nothing }

    var intent: Intent {
        let text = urlText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return .nothing }
        if text.hasPrefix("@") || text.contains("youtube.com") || text.contains("youtu.be")
            || text.hasPrefix("UC") {
            return .open
        }
        return .find
    }

    var isBusy: Bool { listing.isLoading || search.isBusy }

    /// The rows the list shows: the listing, narrowed by the filter field.
    var visible: [Video] {
        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return listing.videos }
        return listing.videos.filter {
            $0.title.lowercased().contains(needle)
                || ($0.channelName?.lowercased().contains(needle) ?? false)
        }
    }

    var allVisiblePicked: Bool {
        let visible = visible
        return !visible.isEmpty && visible.allSatisfy { picked.contains($0.id) }
    }

    var formatLabel: String {
        quality.iosLabel + (alsoAudio && !quality.isAudioOnly ? " + m4a" : "")
    }

    // MARK: - Actions

    func submit() {
        let text = urlText.trimmingCharacters(in: .whitespaces)
        switch intent {
        case .nothing: return
        case .open:
            search.reset()
            listing.open(text)
        case .find:
            listing.reset()
            search.run(text)
        }
    }

    func open(_ channel: Channel) {
        search.reset()
        urlText = ""
        picked = []
        isSelecting = false
        library.markOpened(channel.id)
        listing.open(channel.id, known: channel)
    }

    func goHome() {
        listing.reset()
        search.reset()
        urlText = ""
        filterText = ""
        picked = []
        isSelecting = false
    }

    // MARK: - Selection

    func toggle(_ video: Video) {
        if picked.contains(video.id) { picked.remove(video.id) } else { picked.insert(video.id) }
    }

    func toggleAllVisible() {
        let visible = visible
        if allVisiblePicked {
            for video in visible { picked.remove(video.id) }
        } else {
            for video in visible { picked.insert(video.id) }
        }
    }

    // MARK: - Downloading

    func downloadPicked() {
        let chosen = listing.videos.filter { picked.contains($0.id) }
        guard !chosen.isEmpty else { return }
        download(chosen)
        picked = []
        isSelecting = false
    }

    func download(_ videos: [Video]) {
        downloads.enqueue(videos, quality: quality, alsoAudio: alsoAudio)
        banner = videos.count == 1
            ? "Downloading \(videos[0].title)."
            : "Downloading \(videos.count) videos."
    }

    // MARK: - Saving

    var isListedChannelSaved: Bool {
        guard let channel = listing.channel else { return false }
        return library.contains(channel.id)
    }

    func toggleSavedChannel() {
        guard let channel = listing.channel else { return }
        library.toggle(channel)
    }

    func isSaved(_ video: Video) -> Bool { library.containsVideo(video.id) }

    func toggleSaved(_ video: Video) {
        library.toggleVideo(video, channel: listing.channel)
    }

    // MARK: - Transfer

    func importLibrary(from url: URL) {
        do {
            banner = try library.importArchive(from: url)
        } catch {
            banner = error.localizedDescription
        }
    }

    func importTakeout(from url: URL) {
        do {
            try library.importTakeout(from: url)
            banner = library.note
        } catch {
            banner = error.localizedDescription
        }
    }

    /// Write the library somewhere the export sheet can hand off from.
    func exportLibrary() throws -> URL {
        let name = "\(Paths.appName).\(LibraryArchive.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try library.export(to: url)
        return url
    }
}
