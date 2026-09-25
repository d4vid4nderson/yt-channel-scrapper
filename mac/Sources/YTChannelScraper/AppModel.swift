import AppKit
import AVFoundation
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
    /// Asking for the family panel. Set from a row's ⋯ when it has nothing to offer
    /// yet, and from the landing strip; both are several levels down from the drawer and
    /// have nothing to open it with directly.
    var showFamily: Bool {
        get { showFamilyDrawer }
        set { newValue ? openFamilyDrawer() : (showFamilyDrawer = false) }
    }
    var showChannelsDrawer = false {
        // Opening the saved channels is the moment you are about to pick one.
        didSet { if showChannelsDrawer { warmSavedChannels() } }
    }
    /// Setting up a child's phone over the cable — see `PhoneSetupSheet`.
    var showPhoneSetup = false
    /// Every device and what it holds — see `DevicesSheet`. `focusedDevice` is the one it
    /// opens on, when it was opened by clicking a particular device.
    var showDevices = false
    var focusedDevice: UUID?
    var showFamilyDrawer = false
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

    /// A video still playing after its preview card was closed, shown in the window's
    /// Now Playing bar. The island is only for when the window itself is put away.
    struct NowPlaying {
        let video: Video
        let player: AVPlayer
        let ratio: CGFloat
    }
    private(set) var nowPlaying: NowPlaying? {
        didSet {
            guard nowPlaying?.video.id != oldValue?.video.id else { return }
            presentNowPlaying()
        }
    }

    /// Pre-reads the saved channels, so opening one from the drawer is instant.
    let listingWarmer = ListingWarmer()
    /// The waveform and tempo of whatever is in the Now Playing module.
    let trackAnalysis = TrackAnalysis()

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
    /// Phones this Mac can reach over the cable or Wi-Fi, for syncing them on the spot.
    let nearby = NearbyPhones()
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
        // With what it holds, so the family list can show the computer alongside the phones.
        let folder = Paths.downloads
        let files = await Task.detached { DeviceRecord.scan(folder) }.value
        await shelf.announce(person: (guardian.id, guardian.name), isMinor: false,
                             files: files,
                             freeBytes: DeviceRecord.freeSpace(at: folder),
                             library: .init(channels: library.channels.count,
                                            videos: library.videos.count))
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
        let entry = ShelfEntry(
            kind: .channel, id: channel.id,
            state: approve ? .approved : .removed,
            guardian: guardian.name,
            title: channel.title
        )
        // A removal needs nothing else: blocking a channel already takes its videos off
        // the phone. An approval brings the newest videos with it — see `withLatestVideos`.
        let entries = approve ? await withLatestVideos(entry, as: guardian) : [entry]
        return await shelf.record(entries, for: minor, as: guardian)
    }

    /// Send whatever was dragged onto somebody.
    @discardableResult
    func send(_ item: SendPayload, to minor: Profiles.Minor) async -> Bool {
        guard let guardian = profiles.guardian else { return false }
        let entry = ShelfEntry(
            kind: item.kind, id: item.id,
            state: .approved,
            guardian: guardian.name,
            title: item.title,
            channelID: item.channelID
        )
        let entries = item.kind == .channel ? await withLatestVideos(entry, as: guardian) : [entry]
        return await shelf.record(entries, for: minor, as: guardian)
    }

    /// How many of a channel's newest videos go with it when it is sent.
    static let videosPerChannelSend = 25

    /// A channel approval, plus an approval naming each of its newest videos.
    ///
    /// Approving a channel on its own approves none of its videos — deliberately, so that
    /// something the channel posts next week cannot reach a child unseen (see
    /// `ShelfMerge.playable`). That left sending a channel doing nothing a child could
    /// watch. This keeps the rule and makes sending useful: each video here is named in
    /// its own decision, made now, by the parent who sent it. Anything posted after this
    /// still needs sending.
    ///
    /// If the listing fails the channel still goes, alone, rather than the send failing.
    private func withLatestVideos(_ channel: ShelfEntry, as guardian: Profiles.Guardian) async -> [ShelfEntry] {
        let videos = await latestVideos(ofChannel: channel.id, count: Self.videosPerChannelSend)
        return [channel] + videos.map {
            ShelfEntry(kind: .video, id: $0.id, state: .approved,
                       guardian: guardian.name, title: $0.title, channelID: channel.id)
        }
    }

    /// A channel's newest uploads, newest first, straight from its Videos tab.
    private func latestVideos(ofChannel id: String, count: Int) async -> [Video] {
        let stream = ProcessStream(
            executable: Paths.ytdlp,
            arguments: YtDlp.scrapeArguments(url: "https://www.youtube.com/channel/\(id)/videos",
                                             offset: 0, count: count),
            environment: YtDlp.environment
        )
        var videos: [Video] = []
        do {
            for try await line in stream.lines() {
                guard line.hasPrefix("{"), let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let video = Video(json: json)
                else { continue }
                videos.append(video)
            }
        } catch {
            Log.shelf.error("could not list \(id, privacy: .public) to send: \(error)")
        }
        return videos
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
        // Opening a channel from a set of hits throws those hits away, and the only way
        // back was Home — which also clears the field, so you retyped the search you had
        // just run. Keep them instead; they cost a few dozen structs.
        if mode == .channels, search.hasResults {
            lastSearch = (search.query, search.results)
        }
        mode = .videos
        search.reset()
        picked = []
        filterText = ""
        scraper.start(rawURL: urlText, tab: tab)
    }

    func searchChannels() {
        // These hits become the ones on screen, so there is nothing behind them.
        lastSearch = nil
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

    /// The hits a channel was opened from, if it was opened from any. Held rather than
    /// re-run: see `ChannelSearch.restore`.
    private var lastSearch: (query: String, results: [Channel])?

    /// What the back control says it will return to, and whether to show one at all.
    var searchToReturnTo: String? {
        guard mode != .channels else { return nil }
        return lastSearch?.query
    }

    /// Back to the hits, with the search box saying what it searched for.
    func returnToSearch() {
        guard let last = lastSearch else { return }
        scraper.reset()
        search.restore(query: last.query, results: last.results)
        lastSearch = nil
        startedFromResults = false
        openingChannel = nil
        mode = .channels
        urlText = last.query
        picked = []
        filterText = ""
    }

    /// Back to the landing view, keeping what was typed so it can be edited and re-run.
    func goHome() {
        scraper.reset()
        search.reset()
        lastSearch = nil
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
    /// backdrop, and queueing a download. Closing a card is not the same as saying stop:
    /// a three-hour mix cut off mid-bar because you wanted the list back is the app
    /// taking something away for no reason. So it carries on in the Now Playing bar at
    /// the foot of the window. The island is for when the window goes away, not the
    /// card — see `popOutToIsland`.
    ///
    /// Nothing to hand over if the stream never started — there this is just a close.
    func dismissPreview() {
        if let handed = preview.handOff() {
            nowPlaying?.player.pause()
            nowPlaying = NowPlaying(video: handed.video, player: handed.player, ratio: handed.ratio)
        }
        preview.close()
    }

    /// Back into the full card, from the bar.
    func reopenNowPlaying() {
        guard let now = nowPlaying else { return }
        nowPlaying = nil
        preview.adopt(video: now.video, player: now.player, ratio: now.ratio)
    }

    func warmSavedChannels() {
        listingWarmer.warm(library.recent, tab: tab)
    }

    /// A video asked to play straight into the module, while its stream is found. Its own
    /// session, so the preview card never opens for it.
    private(set) var nowLoading: Video? {
        didSet { if (nowLoading == nil) != (oldValue == nil) { presentNowPlaying() } }
    }
    /// Why `nowLoading` could not play, when it could not.
    private(set) var nowLoadingError: String?
    private let backgroundSession = PreviewSession()
    private var loadingTask: Task<Void, Never>?

    /// The thumbnail's play: start it in the Now Playing module, no card. The card is for
    /// clicking the title.
    func playNow(_ video: Video) {
        if let now = nowPlaying, now.video.id == video.id {
            now.player.play()
            return
        }
        loadingTask?.cancel()
        backgroundSession.close()
        nowLoadingError = nil
        nowLoading = video
        backgroundSession.open(video)
        loadingTask = Task { [weak self] in
            // The session reports through its state; there is nothing to await but it.
            for _ in 0..<600 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled, self.nowLoading?.id == video.id else { return }
                switch self.backgroundSession.state {
                case .working: continue
                case .failed(let message):
                    Log.preview.error("play now failed: \(message, privacy: .public)")
                    // Said in the module itself, which stays up until it is closed.
                    self.nowLoadingError = message
                    return
                case .ready:
                    guard let handed = self.backgroundSession.handOff() else { return }
                    self.nowPlaying?.player.pause()
                    self.nowPlaying = NowPlaying(video: handed.video, player: handed.player,
                                                 ratio: handed.ratio)
                    handed.player.play()
                    self.nowLoading = nil
                    return
                }
            }
            self?.nowLoading = nil
            self?.backgroundSession.close()
        }
    }

    /// The title's link: the full card. Whatever is in Now Playing pauses — two things
    /// sounding at once is nobody's intent.
    func openCard(_ video: Video) {
        cancelNowLoading()
        nowPlaying?.player.pause()
        preview.open(video)
    }

    func cancelNowLoading() {
        loadingTask?.cancel()
        backgroundSession.close()
        nowLoadingError = nil
        nowLoading = nil
    }

    /// The Now Playing module's height, which the window grows by to make room for it.
    static let nowPlayingHeight: CGFloat = 148

    /// How much the window was actually grown for the module, so closing it gives back
    /// exactly that — no more, if the screen only had room for part of it.
    private var grownForNowPlaying: CGFloat = 0

    /// Make room for the module, or give the room back. The window grows downward, so the
    /// page keeps its size and the footer is what moves; against the foot of the screen,
    /// or in full screen, the module takes its height from the page instead.
    func presentNowPlaying() {
        if let now = nowPlaying { trackAnalysis.analyse(now.video) }
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain
        }), !window.styleMask.contains(.fullScreen) else { return }
        var frame = window.frame
        let wanted = nowPlaying != nil || nowLoading != nil
        if wanted, grownForNowPlaying == 0 {
            let floor = (window.screen ?? NSScreen.main)?.visibleFrame.minY ?? frame.minY
            let grow = min(Self.nowPlayingHeight, max(0, frame.minY - floor))
            guard grow > 0 else { return }
            frame.origin.y -= grow
            frame.size.height += grow
            grownForNowPlaying = grow
        } else if !wanted, grownForNowPlaying > 0 {
            frame.origin.y += grownForNowPlaying
            frame.size.height -= grownForNowPlaying
            grownForNowPlaying = 0
        } else {
            return
        }
        window.setFrame(frame, display: true, animate: true)
    }

    func stopNowPlaying() {
        cancelNowLoading()
        guard let now = nowPlaying else { return }
        trackAnalysis.cancel()
        nowPlaying = nil
        now.player.pause()
        now.player.replaceCurrentItem(with: nil)
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
        showFamilyDrawer = false
        showChannelsDrawer = true
    }

    func openFamilyDrawer() {
        showChannelsDrawer = false
        showFamilyDrawer = true
    }

    func toggleChannelsDrawer() {
        if showChannelsDrawer { showChannelsDrawer = false } else { openChannelsDrawer() }
    }

    func toggleFamilyDrawer() {
        if showFamilyDrawer { showFamilyDrawer = false } else { openFamilyDrawer() }
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
        // The open card first; failing that, whatever is going on in the bar.
        let fromBar = nowPlaying.map { (player: $0.player, ratio: $0.ratio, video: $0.video) }
        guard let handed = preview.handOff() ?? fromBar else { return }
        nowPlaying = nil
        islandVideo = handed.video
        miniPlayer.onRestore = { [weak self] in self?.restoreFromIsland() }
        miniPlayer.onClose = { [weak self] in self?.closeIsland() }
        miniPlayer.isSaved = { [weak self] in
            guard let self, let video = islandVideo else { return false }
            return isSaved(video)
        }
        // The page this was popped out from, captured now. `toggleSaved(_ video:)`
        // falls back to whatever is being scraped *at the time of the call*, and the
        // island outlives the page — pop out, go home, save, and a video that arrived
        // without a channel of its own would be filed under an unrelated one. That is
        // not only a wrong label: a channel veto reaches its videos through that id.
        let from = scraper.channelRef
        let fromName = scraper.channel.isEmpty ? nil : scraper.channel
        miniPlayer.onToggleSaved = { [weak self] in
            guard let self, let video = islandVideo else { return }
            library.toggleVideo(video, channel: from, channelName: fromName)
        }
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

    /// The window is back — deminiaturised, or the app unhidden — so the island folds
    /// back into it, as the Now Playing bar. A no-op when the island's own restore
    /// button brought it back, which has already put the video into the card.
    func windowCameBack() {
        guard let video = islandVideo, miniPlayer.isShowing else { return }
        let ratio = miniPlayer.aspectRatio
        guard let player = miniPlayer.release() else { return }
        islandVideo = nil
        nowPlaying = NowPlaying(video: video, player: player, ratio: ratio)
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
