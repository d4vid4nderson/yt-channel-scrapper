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
    /// Whether this is the parent's phone or a minor's. Read by nearly every screen —
    /// it decides which tabs exist and which buttons are on them.
    let profiles = Profiles()
    /// The shared folder both guardians write to: the roster of children, and what each
    /// of them is allowed to see. Separate from `library` on purpose — `library` is what
    /// *you* saved and is nobody else's business, `shelf` is what the two of you have
    /// agreed a child may have.
    let shelf = ShelfStore()
    /// Keeps a minor's phone matching its shelf. Idle on a guardian's phone — there is
    /// nothing to reconcile until the device belongs to a child.
    let reconciler = ShelfReconciler()
    let downloads = Downloads()
    let playback = Playback()
    /// What is already on the phone. `Downloads` only knows about this run's jobs; this
    /// is the folder itself, and it is what survives a relaunch.
    let localFiles = LocalFiles()

    init() {
        // A finished job leaves a new file in Documents, and the on-disk list is a scan
        // rather than an index — so it has to be told to look again.
        downloads.didSave = { [weak self] in self?.localFiles.reload() }
    }

    /// Re-read the shared folder and, on a minor's phone, make the disk match it.
    ///
    /// One call for both halves because they are never wanted apart: a refresh that did
    /// not reconcile would show a child a shelf the phone cannot play, and a reconcile
    /// on a stale read would act on decisions that have since changed. Called on every
    /// foreground.
    func syncShelf() async {
        await shelf.refresh()

        // A minor's phone: reconcile, then say what it actually holds. The gap between
        // approved and downloaded is the number a parent wants — it is the download that
        // has not finished — and this device is the only thing that can report it.
        if let minor = profiles.minor {
            await reconciler.reconcile(for: minor,
                                       shelf: shelf,
                                       downloads: downloads,
                                       localFiles: localFiles)
            // The shelf is this device's library, so anything on it belongs on the
            // shelves the child actually browses.
            claimSent()

            let approved = shelf.approved(for: minor.id).count
            await shelf.announce(person: (minor.id, minor.name),
                                 isMinor: true,
                                 approved: approved,
                                 downloaded: max(0, approved - reconciler.awaiting))
            return
        }

        // A guardian's phone: appear on the family list even before a first approval, and
        // report this device.
        guard let guardian = profiles.guardian else { return }
        await shelf.announce(guardian: guardian)

        // Deliberately no reconcile. An admin's device used to fetch whatever was sent to
        // it, which fought the inbox it was sent to: the inbox offers keep-or-ignore and
        // the download had already happened either way — cancel it and the next sync
        // fetched it again, because as far as the reconciler was concerned it was
        // approved and missing.
        //
        // Nothing lands on an adult's disk without them asking. A minor's device is the
        // opposite and reconciles on purpose: there the shelf *is* the contract.
        let approved = shelf.approved(for: guardian.id).count
        await shelf.announce(person: (guardian.id, guardian.name),
                             isMinor: false,
                             approved: approved,
                             downloaded: approved - inboxCount)
    }

    // MARK: - Input

    var urlText = ""
    /// 720p, where the Mac defaults to 1080p, and deliberately so. YouTube serves a
    /// far higher bitrate at 1080p than at 720p — measured on one hour-long video,
    /// 1.23 GB against 60 MB, a factor of twenty-one — and on a screen this size the
    /// difference is close to invisible while the download is not. The picker still
    /// offers 1080p and Best for anyone who wants them.
    var quality: Quality = .p720
    /// Whether an m4a is wanted beside the video as well as the video itself.
    var alsoAudio = false
    var filterText = ""

    /// Which videos are ticked for a batch download. Empty means the toolbar acts on
    /// whatever row you tap instead.
    var picked: Set<String> = []
    var isSelecting = false

    /// What the player sheet is showing, if anything — a stream or a file on disk.
    var playing: Playable?

    /// Whether the minor is holding it. The screens ask this rather than `profiles`
    /// directly, because "is this the minor" is the question every one of them has and
    /// which profile it is is not.
    var isMinor: Bool { profiles.isMinor }

    /// Which tab is on screen. Bound rather than left to `TabView` so that finishing a
    /// download can take you to it.
    ///
    /// `.search` stays in the enum in Minor Mode even though the tab is not offered —
    /// removing the case would mean every switch over it needing a minor-only shape.
    /// `enterMinorMode()` makes sure nothing is left pointing at it.
    enum Tab: Hashable { case home, search, inbox, downloads }
    var tab: Tab = .home

    /// The pushed channel stack for each tab that has one. Held here rather than in the
    /// views so that a video can send you to the channel it came from, from anywhere —
    /// including the player sheet, which sits above every tab and has no stack of its
    /// own to push onto.
    var homePath: [Channel] = []
    var searchPath: [Channel] = []

    /// Show a channel, on whichever stack is currently in front.
    func show(_ channel: Channel) {
        switch tab {
        case .home:      homePath.append(channel)
        case .search where !isMinor: searchPath.append(channel)
        default:         tab = .home; homePath.append(channel)
        }
    }

    /// Hand the phone over. The mode is already switched by the time this runs; what is
    /// left is making sure nothing the parent had open is still on screen underneath —
    /// a search results list, a half-made selection, or the Search tab itself, which is
    /// about to stop existing.
    func enterMinorMode() {
        tab = .home
        searchPath = []
        clearSearch()
        picked = []
        isSelecting = false
    }

    /// The channel a video came from, as much of one as a row knows.
    ///
    /// A saved copy is preferred when there is one — it carries the avatar and the
    /// subscriber count, which a search result's byline does not. Otherwise the id and
    /// name are enough to open it, and `Listing` fills in the rest.
    func channel(of video: Video) -> Channel? {
        guard let id = video.channelId, !id.isEmpty else { return nil }
        if let saved = library.channels.first(where: { $0.id == id }) { return saved }
        return Channel(id: id, title: video.channelName ?? id)
    }

    // MARK: - What has been sent to this device

    /// Everything currently on this device's own shelf, as library items.
    ///
    /// The shelf stores decisions, not objects: a `ShelfEntry` is an id, a title and —
    /// for a video — its channel. That is deliberately all a receiving device needs, and
    /// it is why this phone can draw what it was sent without asking YouTube anything.
    /// Rebuilding a `Channel` or `Video` from those three fields is the last step.
    var sent: (channels: [Channel], videos: [Video]) {
        guard let me = profiles.minor.map({ ($0.id, $0.name) })
                ?? profiles.guardian.map({ ($0.id, $0.name) })
        else { return ([], []) }

        let standing = ShelfMerge.resolve(shelf.entries(for: me.0)).values
            .filter { $0.state == .approved }

        let channels = standing
            .filter { $0.kind == .channel }
            .map { Channel(id: $0.id, title: $0.title ?? $0.id) }
        let videos = standing
            .filter { $0.kind == .video }
            .compactMap { entry -> Video? in
                var json: [String: Any] = ["id": entry.id, "title": entry.title ?? entry.id]
                if let channelID = entry.channelID { json["channel_id"] = channelID }
                return Video(json: json)
            }
        return (channels, videos)
    }

    /// Keys this device has dismissed from its inbox.
    ///
    /// Per device, not shared: the shelf records what the family decided, and a decision
    /// is not undone by one person tidying their own inbox. It also has to be persisted
    /// or every relaunch would hand back everything already dealt with.
    private(set) var dismissed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "inbox.dismissed") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "inbox.dismissed") }
    }

    private func key(_ kind: ShelfEntry.Kind, _ id: String) -> String { "\(kind.rawValue):\(id)" }

    /// What is still in the inbox.
    ///
    /// Filtered by what has been dismissed. Keeping something dismisses it, so saving and
    /// clearing amount to the same thing — which is the point: an inbox is a list of
    /// things not yet dealt with, and something you have kept is dealt with.
    ///
    /// This was the other way round for a while, on the grounds that you might want to
    /// save *and* download and the row vanishing took the download with it. That reason
    /// went away when Download moved onto the row's ⋯ menu — and it was the weaker of the
    /// two anyway, since a kept video is on the Home shelf with the same menu on it.
    var unclaimedSent: (channels: [Channel], videos: [Video]) {
        let all = sent
        let gone = dismissed
        return (all.channels.filter { !gone.contains(key(.channel, $0.id)) },
                all.videos.filter { !gone.contains(key(.video, $0.id)) })
    }

    /// Take one thing off this device's inbox. Nothing about the family's decision
    /// changes — the sender still sent it, and it stays on the shelf.
    func dismiss(channel: Channel) { dismissed.insert(key(.channel, channel.id)) }
    func dismiss(video: Video) { dismissed.insert(key(.video, video.id)) }

    /// Keep one thing, which is the same act as taking it off the list.
    ///
    /// One verb rather than two calls at each site, so "saved but still sitting in the
    /// inbox" is not a state anything can leave behind by forgetting the second call.
    func keep(channel: Channel) {
        if !library.contains(channel.id) { library.add(channel) }
        dismiss(channel: channel)
    }

    func keep(video: Video) {
        if !library.containsVideo(video.id) { library.toggleVideo(video, channel: nil) }
        dismiss(video: video)
    }

    func isKept(_ channel: Channel) -> Bool { library.contains(channel.id) }
    func isKept(_ video: Video) -> Bool { library.containsVideo(video.id) }

    var inboxCount: Int {
        let waiting = unclaimedSent
        return waiting.channels.count + waiting.videos.count
    }

    /// Put everything waiting into the library.
    ///
    /// Done automatically on a minor's device and offered as a choice on a guardian's.
    /// A minor did not ask for any of it and has no use for an inbox — the shelf *is*
    /// their library, and a screen asking them to accept what a parent already decided
    /// would be ceremony. An adult being sent something by another adult is a suggestion,
    /// and a suggestion you cannot decline is not one.
    func claimSent() {
        let waiting = unclaimedSent
        for channel in waiting.channels { keep(channel: channel) }
        for video in waiting.videos { keep(video: video) }
    }

    /// Set by a row's ⋯ menu when it has nothing to offer because the family has not
    /// been set up. `HomeView` watches it and opens the screen — the menu itself is
    /// several levels down and has no sheet of its own to present from.
    var wantsFamilySetup = false

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

    /// Point the shared `Listing` at a channel, for the screen about to show it.
    ///
    /// It no longer resets the search or changes tabs the way `open` did. Under push
    /// navigation the list you came from is still underneath you and should be exactly
    /// as you left it — clearing it was only ever necessary because the listing had to
    /// take over the screen the search was using.
    func beginListing(_ channel: Channel) {
        guard listing.channel?.id != channel.id else { return }
        picked = []
        isSelecting = false
        filterText = ""
        library.markOpened(channel.id)
        listing.open(channel.id, known: channel)
    }

    /// Empty the search and its results. Was `goHome`, which it stopped being when
    /// Home became a tab of its own.
    func clearSearch() {
        search.reset()
        urlText = ""
        filterText = ""
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
        // Every button that calls this is already hidden in Minor Mode. The guard is here
        // anyway: one missed swipe action in a future edit would otherwise be a silent
        // hole, and this is the single place they all funnel through.
        guard !isMinor else { return }
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

    // MARK: - Playing

    func play(_ video: Video) { playing = .stream(video) }
    func play(_ file: LocalFile) { playing = .local(file) }

    /// What the sheet asks for when it appears.
    ///
    /// Not always an open: coming back to a video you left playing should find it where
    /// it got to, not start it again from the top. Anything else — a different video, or
    /// the same one after it failed — is a real open.
    func resume(_ item: Playable) {
        if case .ready = playback.state, playback.item?.id == item.id { return }
        playback.open(item)
    }

    /// Leave the player, and let it play on. The bar above the tabs is where it goes.
    func leavePlayer() {
        playback.leave()
        playing = nil
    }

    /// Stop it for good — the bar's own X, and the only thing in the app that means
    /// silence now.
    func stopPlaying() {
        playback.close()
        playing = nil
    }

    // MARK: - Transfer

    /// A picked library file, read but not yet taken.
    ///
    /// Held between the document picker closing and the import sheet's button, so the
    /// sheet can say what is actually in the file rather than asking anyone to choose
    /// blind. The archive travels in memory: the URL's security scope belongs to the
    /// picker's callback and is not something to still be holding a minute later.
    struct PendingImport: Identifiable {
        let id = UUID()
        let archive: LibraryArchive
        let filename: String
    }

    var pendingImport: PendingImport?

    /// Read a picked file and put the choice of what to take from it on screen.
    func offerImport(from url: URL) {
        do {
            pendingImport = PendingImport(archive: try Library.read(from: url),
                                          filename: url.lastPathComponent)
        } catch {
            banner = error.localizedDescription
        }
    }

    func takeImport(_ contents: Library.Contents) {
        guard let pending = pendingImport else { return }
        banner = library.merge(pending.archive, contents: contents)
        pendingImport = nil
    }

    func importTakeout(from url: URL) {
        do {
            try library.importTakeout(from: url)
            banner = library.note
        } catch {
            banner = error.localizedDescription
        }
    }

    /// Write a hand-picked subset out for sending on.
    ///
    /// Named for what it holds rather than dated like a full export: this file is aimed
    /// at one person, and "3 channels" tells whoever receives it what they are about to
    /// import where a timestamp would not.
    func exportSelection(channelIDs: Set<String>, videoIDs: Set<String>) throws -> URL {
        let picked = library.archive(channelIDs: channelIDs, videoIDs: videoIDs)
        let what = Library.summary(of: picked)
        let name = "\(Paths.displayName) — \(what).\(LibraryArchive.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try picked.write(to: url)
        return url
    }

    /// Write some or all of the library somewhere the share sheet can hand off from.
    ///
    /// The filename says which halves are in it — a phone's share sheet shows the name
    /// and nothing else, and "Library" twice in a row is no help to whoever is picking
    /// one to send on.
    func exportLibrary(_ contents: Library.Contents) throws -> URL {
        let what = contents == .both ? "Library" : contents.short
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let name = "\(Paths.displayName) \(what) \(stamp).\(LibraryArchive.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try library.export(contents, to: url)
        return url
    }
}
