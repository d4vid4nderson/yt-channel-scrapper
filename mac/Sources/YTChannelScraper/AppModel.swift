import AppKit
import Foundation

@MainActor
@Observable
final class AppModel {
    var urlText = ""
    var tab: ChannelTab = .videos
    var quality: Quality = .p1080
    var filterText = ""
    var picked: Set<String> = []
    var showDownloads = false
    /// What the island is playing, so it can be put back where it came from.
    var islandVideo: Video?

    let scraper = Scraper()
    let downloader = Downloader()
    let updater = Updater()
    let preview = PreviewSession()
    let miniPlayer = MiniPlayer()

    var visible: [Video] {
        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return scraper.videos }
        return scraper.videos.filter { $0.title.lowercased().contains(needle) }
    }

    var hasResults: Bool { !scraper.videos.isEmpty }

    var canScrape: Bool {
        !urlText.trimmingCharacters(in: .whitespaces).isEmpty && !scraper.isBusy
    }

    /// Select-all applies to what the filter is currently showing, so narrowing the list
    /// and ticking the box is a way to select a subset.
    var allVisiblePicked: Bool {
        let visible = visible
        return !visible.isEmpty && visible.allSatisfy { picked.contains($0.id) }
    }

    func scrape() {
        guard canScrape else { return }
        picked = []
        filterText = ""
        scraper.start(rawURL: urlText, tab: tab)
    }

    /// Back to the landing view, keeping what was typed so it can be edited and re-run.
    func goHome() {
        scraper.reset()
        picked = []
        filterText = ""
    }

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

    func downloadPicked() {
        download(scraper.videos.filter { picked.contains($0.id) })
        picked = []
    }

    /// Also the per-row button's path, which queues one video without touching the
    /// wider selection.
    func download(_ videos: [Video]) {
        guard !videos.isEmpty else { return }
        downloader.enqueue(videos, quality: quality)
        showDownloads = true
    }
}


// MARK: - The island

extension AppModel {
    /// Move a playing preview up to the island. Called when the window is minimised, and
    /// by the modal's own pop-out button.
    func popOutToIsland() {
        guard let handed = preview.handOff() else { return }
        islandVideo = handed.video
        miniPlayer.onRestore = { [weak self] in self?.restoreFromIsland() }
        miniPlayer.onClose = { [weak self] in self?.closeIsland() }
        miniPlayer.show(
            player: handed.player,
            title: handed.video.title,
            aspectRatio: handed.ratio
        )
    }

    func restoreFromIsland() {
        let ratio = miniPlayer.aspectRatio
        guard let video = islandVideo, let player = miniPlayer.release() else { return }
        islandVideo = nil
        preview.adopt(video: video, player: player, ratio: ratio)
        NSApp.windows.first { $0.isMiniaturized }?.deminiaturize(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeIsland() {
        islandVideo = nil
        miniPlayer.release()?.pause()
    }
}
