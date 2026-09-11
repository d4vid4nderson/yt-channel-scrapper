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
    /// The two favourites drawers. Held here rather than in the view so the menu bar can
    /// reach them, and so each can close the others — three panels over one page at once
    /// would be two too many.
    var showChannelsDrawer = false
    var showVideosDrawer = false
    /// Whether the results area is listing a channel's videos or a search's channels.
    /// Held rather than derived, so it flips on submit instead of when results land —
    /// otherwise the old list is still on screen while the new one is being fetched.
    private(set) var mode: Mode = .videos
    /// What the island is playing, so it can be put back where it came from.
    var islandVideo: Video?

    let scraper = Scraper()
    let search = ChannelSearch()
    let library = Library()
    let downloader = Downloader()
    let updater = Updater()
    let appUpdater = AppUpdater()
    let preview = PreviewSession()
    let miniPlayer = MiniPlayer()

    /// The video list the results area is showing — a channel's, or the saved ones.
    /// Everything downstream of this (filtering, select-all, download) works the same
    /// either way, which is what makes the saved list a place you can act from rather
    /// than just look at.
    var listedVideos: [Video] { mode == .saved ? library.videos : scraper.videos }

    /// The rows on screen, in order: kept first, then the rest.
    ///
    /// A channel you come back to is usually a channel you already found something in,
    /// and hunting back down a 5,000-video list for it defeats the point of having kept
    /// it. Each group holds the channel's own order underneath, so nothing is scrambled
    /// — the kept ones are lifted out, not re-sorted.
    var visible: [Video] { keptVisible + restVisible }

    /// The kept videos belonging to the channel on screen.
    ///
    /// Taken from the library rather than from what has been scraped, deliberately: a
    /// video you kept may sit four hundred entries down the channel, and lifting it to
    /// the top means nothing if you have to page down to it first. So it is shown above
    /// the listing whether or not the listing has reached it yet.
    ///
    /// Empty in the saved list, where every row is kept and lifting them would say
    /// nothing.
    var keptVisible: [Video] {
        guard mode == .videos else { return [] }
        return library.videos.filter { isFromCurrentChannel($0) && matchesFilter($0) }
    }

    var restVisible: [Video] {
        let kept = Set(keptVisible.map(\.id))
        return listedVideos.filter { !kept.contains($0.id) && matchesFilter($0) }
    }

    /// Prefer the id: channel names collide, and get changed. The name is the fallback
    /// for videos kept before the id was recorded.
    private func isFromCurrentChannel(_ video: Video) -> Bool {
        if let current = scraper.channelRef?.id, let owner = video.channelId {
            return owner == current
        }
        return !scraper.channel.isEmpty && video.channelName == scraper.channel
    }

    private func matchesFilter(_ video: Video) -> Bool {
        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        return needle.isEmpty || video.title.lowercased().contains(needle)
    }

    enum Mode { case videos, channels, saved }

    /// What pressing return does. A URL or an @handle names one channel, so it gets
    /// scraped; anything else is words, and words are a search. Same field either way —
    /// the point is not having to know which kind of thing you have before you type it.
    enum Intent { case scrape, search }

    var intent: Intent {
        let text = urlText.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("@") || text.hasPrefix("http")
            || text.contains("youtube.com") || text.contains("youtu.be") {
            return .scrape
        }
        return .search
    }

    /// The header collapses once there is a list to show, whichever kind it is.
    var hasResults: Bool {
        switch mode {
        case .videos:   !scraper.videos.isEmpty
        case .channels: search.hasResults
        case .saved:    !library.videos.isEmpty
        }
    }

    var isBusy: Bool {
        switch mode {
        case .videos:   scraper.isBusy
        case .channels: search.isBusy
        case .saved:    false
        }
    }

    var statusError: String? {
        switch mode {
        case .videos:   scraper.error
        case .channels: search.error
        case .saved:    nil
        }
    }

    var canScrape: Bool {
        !urlText.trimmingCharacters(in: .whitespaces).isEmpty && !isBusy
    }

    /// Select-all applies to what the filter is currently showing, so narrowing the list
    /// and ticking the box is a way to select a subset.
    var allVisiblePicked: Bool {
        let visible = visible
        return !visible.isEmpty && visible.allSatisfy { picked.contains($0.id) }
    }

    /// The one entry point the search pill's button and its return key both use.
    func submit() {
        guard canScrape else { return }
        switch intent {
        case .scrape: scrape()
        case .search: searchChannels()
        }
    }

    func stop() {
        mode == .channels ? search.stop() : scraper.stop()
    }

    func scrape() {
        guard canScrape else { return }
        mode = .videos
        search.reset()
        picked = []
        filterText = ""
        scraper.start(rawURL: urlText, tab: tab)
    }

    func searchChannels() {
        mode = .channels
        scraper.reset()
        picked = []
        filterText = ""
        search.run(urlText)
    }

    /// Show the saved videos in place of a channel's, so they can be ticked, previewed
    /// and downloaded with exactly the machinery a scrape's list uses.
    func showSavedVideos() {
        mode = .saved
        scraper.reset()
        search.reset()
        picked = []
        filterText = ""
    }

    /// Open a channel — from a search hit, or from the saved shelf. Putting its URL in
    /// the field first means the scrape is one you could have typed, and leaves it there
    /// to edit.
    func open(_ channel: Channel) {
        library.markOpened(channel.id)
        urlText = channel.url
        scrape()
    }

    /// Back to the landing view, keeping what was typed so it can be edited and re-run.
    func goHome() {
        scraper.reset()
        search.reset()
        mode = .videos
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
        download(listedVideos.filter { picked.contains($0.id) })
        picked = []
    }

    /// Also the per-row button's path, which queues one video without touching the
    /// wider selection.
    func download(_ videos: [Video]) {
        guard !videos.isEmpty else { return }
        downloader.enqueue(videos, quality: quality)
        openDownloads()
    }
}


// MARK: - Drawers

extension AppModel {
    /// Downloads sits along the bottom and can be up alongside either side panel — none
    /// of them covers anything, so there is nothing to be gained by making them fight.
    ///
    /// The two side panels are the exception: they take width from the same page, and at
    /// the window's minimum size both at once would leave the list too narrow to read.
    func openChannelsDrawer() {
        showVideosDrawer = false
        showChannelsDrawer = true
    }

    func openVideosDrawer() {
        showChannelsDrawer = false
        showVideosDrawer = true
    }

    func toggleChannelsDrawer() {
        if showChannelsDrawer { showChannelsDrawer = false } else { openChannelsDrawer() }
    }

    func toggleVideosDrawer() {
        if showVideosDrawer { showVideosDrawer = false } else { openVideosDrawer() }
    }

    func openDownloads() {
        showDownloads = true
    }

    func toggleDownloads() {
        if showDownloads { showDownloads = false } else { openDownloads() }
    }
}


// MARK: - The island

extension AppModel {
    /// Move a playing preview up to the island.
    ///
    /// Two ways in, and they want opposite things of the window. Minimising the window is
    /// already the user putting it away, so the island simply follows; pressing the
    /// player's own button is the user asking for the island, and leaving a full-size
    /// window sitting behind it would be answering half the request — so that one takes
    /// the window down as well.
    func popOutToIsland(tuckingWindowAway: Bool = false) {
        guard let handed = preview.handOff() else { return }
        islandVideo = handed.video
        miniPlayer.onRestore = { [weak self] in self?.restoreFromIsland() }
        miniPlayer.onClose = { [weak self] in self?.closeIsland() }
        miniPlayer.show(
            player: handed.player,
            title: handed.video.title,
            aspectRatio: handed.ratio
        )
        // After the island is up, so the picture never has nowhere to be: miniaturising
        // first would take the window down with the preview still inside it.
        if tuckingWindowAway {
            NSApp.windows
                .first { $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain }?
                .miniaturize(nil)
        }
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


// MARK: - Saved channels

extension AppModel {
    /// The channel currently on screen, if there is one to save: the one being scraped.
    var scrapedChannel: Channel? { scraper.channelRef }

    var isScrapedChannelSaved: Bool {
        guard let scrapedChannel else { return false }
        return library.contains(scrapedChannel.id)
    }

    func toggleSaved(_ channel: Channel) {
        library.toggle(channel)
    }

    func isSaved(_ video: Video) -> Bool { library.containsVideo(video.id) }

    /// The channel name comes off the header when the video itself does not carry one,
    /// so a saved video can always say where it came from.
    func toggleSaved(_ video: Video) {
        library.toggleVideo(
            video,
            channel: scraper.channelRef,
            channelName: scraper.channel.isEmpty ? nil : scraper.channel
        )
    }

    /// Write everything kept to one file, to be carried to another Mac.
    func exportLibrary() {
        let panel = NSSavePanel()
        panel.title = "Export Library"
        panel.message = "Everything you have saved — channels and videos — in one file you can copy to another Mac."
        panel.prompt = "Export"
        panel.nameFieldStringValue = LibraryArchive.suggestedFilename
        panel.allowedContentTypes = [.ytcsLibrary]
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try library.export(to: url)
        } catch {
            library.report("Could not write \(url.lastPathComponent).")
        }
    }

    func importLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Import Library"
        panel.message = "Choose a library exported from another Mac. Anything already here is kept."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.ytcsLibrary]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importLibrary(from: url)
    }

    /// Take whatever the Finder handed the app while it was starting, or since.
    func drainOpenedLibraries() {
        let waiting = AppDelegate.pendingLibraries
        guard !waiting.isEmpty else { return }
        AppDelegate.pendingLibraries = []
        for url in waiting { importLibrary(from: url) }
    }

    /// Also the path a dropped file and a double-clicked one take.
    func importLibrary(from url: URL) {
        do {
            try library.merge(archiveAt: url)
        } catch {
            library.report(
                (error as? LibraryArchive.Failure)?.errorDescription
                    ?? "Could not read \(url.lastPathComponent)."
            )
        }
        // Opened either way: the result is a line in that panel, and an import that
        // reports into a drawer you cannot see has not reported anything.
        showChannelsDrawer = true
    }

    /// Ask for a Google Takeout `subscriptions.csv` and merge it into the saved list.
    ///
    /// This is the no-sign-in route to "the channels I'm subscribed to": YouTube will
    /// export them, and one file is a great deal less machinery than an OAuth client
    /// that Google has to review.
    func importSubscriptions() {
        let panel = NSOpenPanel()
        panel.title = "Import YouTube Subscriptions"
        panel.message = "Choose the subscriptions.csv from your Google Takeout export."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importSubscriptions(from: url)
    }

    /// Also the drop target's path, so the file can just be dragged onto the shelf.
    func importSubscriptions(from url: URL) {
        do {
            try library.importTakeout(from: url)
        } catch {
            library.report("Could not read \(url.lastPathComponent).")
        }
        showChannelsDrawer = true
    }
}
