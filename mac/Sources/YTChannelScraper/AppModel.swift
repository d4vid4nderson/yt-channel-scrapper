import AppKit
import Foundation

@MainActor
@Observable
final class AppModel {
    var urlText = ""
    var tab: ChannelTab = .videos
    var quality: Quality = .p1080
    /// Whether a download leaves an mp3 beside the video as well as the video itself.
    /// Useful for anything you want to listen to as well as watch — a mix, a talk, a
    /// podcast — without paying for the download twice.
    var alsoAudio = false
    var filterText = ""
    var picked: Set<String> = []
    var showDownloads = false
    /// The two favourites drawers. Held here rather than in the view so the menu bar can
    /// reach them, and so each can close the others — three panels over one page at once
    /// would be two too many.
    /// Whether the family setup sheet is up. Set from a row's ⋯ when it has nothing to
    /// offer yet, and from the app menu.
    var showFamily = false
    var showChannelsDrawer = false
    var showVideosDrawer = false
    /// Whether the results area is listing a channel's videos or a search's channels.
    /// Held rather than derived, so it flips on submit instead of when results land —
    /// otherwise the old list is still on screen while the new one is being fetched.
    private(set) var mode: Mode = .videos
    /// Whether the run that is going was started from inside the results area. Read only
    /// while something is running, to decide whether the wait belongs there or in the hero.
    private var startedFromResults = false
    /// The channel a scrape was started *for*, when it was started by name rather than by
    /// typing a URL. Kept only for what the wait says while the first page is fetched.
    private(set) var openingChannel: Channel?
    /// What the island is playing, so it can be put back where it came from.
    var islandVideo: Video?

    let scraper = Scraper()
    let search = ChannelSearch()
    let library = Library()
    /// Who this Mac's owner is, for signing approvals. Minor Mode's PIN comes along with
    /// the type and goes unused here — a Mac is a guardian's machine.
    let profiles = Profiles()
    /// What the family has agreed each child may see. The Mac is the big screen this is
    /// worth curating on, which is the whole reason the store was promoted out of the
    /// iOS target.
    let shelf = ShelfStore()
    let downloader = Downloader()
    let updater = Updater()
    let appUpdater = AppUpdater()
    let preview = PreviewSession()
    let miniPlayer = MiniPlayer()

    /// The video list the results area is showing — a channel's, or the saved ones.
    /// Everything downstream of this (filtering, select-all, download) works the same
    /// either way, which is what makes the saved list a place you can act from rather
    /// than just look at.
    /// Re-read the shared folder. Cheap, and the only honest moment to do it is when
    /// this machine comes back to the front — the other guardian's device writes into
    /// that folder and nothing here is notified.
    func syncShelf() async {
        await shelf.refresh()
        guard let guardian = profiles.guardian else { return }
        // Put this guardian on the family list even before their first approval, so the
        // other parent sees them appear as soon as they are set up rather than whenever
        // they happen to approve something.
        await shelf.announce(guardian: guardian)
        // And say this machine exists. Every refresh, not once: `lastSeen` is the field
        // that makes the row worth showing, and one written at setup would go stale.
        await shelf.announce(person: (guardian.id, guardian.name), isMinor: false)
    }

    /// Put an approval — or its withdrawal — in this guardian's file.
    ///
    /// Writes a whole `ShelfEntry` rather than calling `ShelfStore.set`, because an entry
    /// carries its own title and, for a video, its channel: the child's device names its
    /// downloads from the first and a later channel veto reaches this video through the
    /// second.
    @discardableResult
    func send(_ video: Video, to minor: Profiles.Minor, approve: Bool) async -> Bool {
        guard let guardian = profiles.guardian else { return false }
        return await shelf.record([ShelfEntry(
            kind: .video, id: video.id,
            state: approve ? .approved : .removed,
            guardian: guardian.name,
            title: video.title,
            channelID: video.channelId
        )], for: minor, as: guardian)
    }

    @discardableResult
    func send(_ channel: Channel, to minor: Profiles.Minor, approve: Bool) async -> Bool {
        guard let guardian = profiles.guardian else { return false }
        return await shelf.record([ShelfEntry(
            kind: .channel, id: channel.id,
            state: approve ? .approved : .removed,
            guardian: guardian.name,
            title: channel.title
        )], for: minor, as: guardian)
    }

    /// Whether this item is on that child's shelf right now.
    func isOnShelf(kind: ShelfEntry.Kind, id: String, for minor: Profiles.Minor) -> Bool {
        shelf.approved(for: minor.id).contains(ShelfEntry.Key(kind: kind, id: id))
    }

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

    /// Whether the page is showing the results area rather than the hero.
    ///
    /// Deliberately not just `hasResults`. Starting a scrape empties the list a second or
    /// two before the next one arrives, and a page that fell back to the hero for that
    /// gap would throw away where you were every time you opened another channel from the
    /// panel — you asked for a channel and got the landing screen back. So once you are in
    /// the results you stay in them, and the wait is drawn there instead, as the shape of
    /// the list that is coming.
    var showsResults: Bool { hasResults || (isBusy && startedFromResults) }

    /// A list on its way with nothing of it on screen yet — what the skeleton rows stand
    /// in for. Loading *more* of a list is not this: that has rows above it already, and
    /// a spinner at the foot is the honest thing there.
    var isLoadingList: Bool {
        switch mode {
        case .videos:   scraper.isBusy && scraper.videos.isEmpty
        case .channels: search.isBusy && search.results.isEmpty
        case .saved:    false
        }
    }

    /// Whose videos are being read, while they are being read. The scraper does not know
    /// the channel's name until the first page answers, so a scrape started from a saved
    /// channel or a search hit carries the name in with it — the wait can then say which
    /// channel you are waiting for rather than sitting on "0 videos".
    var loadingChannelName: String? {
        guard mode == .videos, isLoadingList else { return nil }
        return scraper.channel.isEmpty ? openingChannel?.title : scraper.channel
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

    func scrape(opening channel: Channel? = nil) {
        guard canScrape else { return }
        // Both read the state the last run left behind, so they are taken before it goes.
        startedFromResults = hasResults
        openingChannel = channel
        mode = .videos
        search.reset()
        picked = []
        filterText = ""
        scraper.start(rawURL: urlText, tab: tab)
    }

    func searchChannels() {
        startedFromResults = hasResults
        openingChannel = nil
        mode = .channels
        scraper.reset()
        picked = []
        filterText = ""
        search.run(urlText)
    }

    /// Show the saved videos in place of a channel's, so they can be ticked, previewed
    /// and downloaded with exactly the machinery a scrape's list uses.
    func showSavedVideos() {
        startedFromResults = false
        openingChannel = nil
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
        scrape(opening: channel)
    }

    /// Back to the landing view, keeping what was typed so it can be edited and re-run.
    func goHome() {
        scraper.reset()
        search.reset()
        startedFromResults = false
        openingChannel = nil
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

    /// What the quality picker shows on its face, and what the download button promises:
    /// the quality, plus the mp3 when one is coming with it.
    var formatLabel: String {
        alsoAudio && !quality.isAudioOnly ? "\(quality.label) + mp3" : quality.label
    }

    func downloadPicked() {
        download(listedVideos.filter { picked.contains($0.id) })
        picked = []
    }

    /// Also the per-row button's path, which queues one video without touching the
    /// wider selection.
    func download(_ videos: [Video]) {
        guard !videos.isEmpty else { return }
        downloader.enqueue(videos, quality: quality, alsoAudio: alsoAudio)
        openDownloads()
    }

    /// Put the preview card away without stopping what it was playing.
    ///
    /// Every way out of the card comes through here — the X, Escape, a click on the
    /// backdrop, and queueing a download. Closing a window is not the same as saying
    /// stop: a three-hour mix cut off mid-bar because you wanted the list back is the
    /// app taking something away for no reason. So the picture moves up to the island,
    /// which is where a video that has outlived its window already goes, and the sound
    /// carries on until you pull it back down or press the island's own X.
    ///
    /// Nothing to hand over if the stream never started — there this is just a close.
    func dismissPreview() {
        popOutToIsland()
        preview.close()
    }

    /// Queue what the preview is playing, and leave it playing. The downloads panel the
    /// queueing opens is then something to watch the fetch in, not an interruption.
    func downloadPreviewed(_ video: Video) {
        download([video])
        dismissPreview()
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
