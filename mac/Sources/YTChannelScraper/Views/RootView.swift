import AppKit
import Combine
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Namespace private var hero

    /// The hero holds the whole window until there is something to show, then collapses
    /// to a header — the same move the web app made, and for the same reason: the search
    /// is the whole app until it isn't.
    ///
    /// Once collapsed it stays collapsed through the next scrape as well: `showsResults`
    /// counts a list on its way as a list, so opening a channel from the panel loads in
    /// front of you instead of putting the hero back over the page you were reading.
    private var collapsed: Bool { model.showsResults }

    /// One easing for the entire landing -> app transition, matching the web app's
    /// `cubic-bezier(.4, 0, .2, 1)` over .65s.
    private static let morph = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.65)

    /// The panels take room from the page rather than covering it, so whatever you were
    /// looking at is still there — and still usable — while you dig through what you have
    /// kept. Nothing is dimmed, because nothing is blocked.
    private var isClassic: Bool { Theme.active.id == .classic }
    @State private var isFullScreen = false
    /// The header row — home, the channel, the search — folded away, for more of the
    /// player and the list. Only ever folds the collapsed header, never the hero, and is
    /// remembered between launches. The View menu and the title-bar button both flip it.
    @AppStorage("header.hidden") private var headerHidden = false
    /// The player taking the whole results area, the list folded away under it. Set from
    /// `PreviewPanel` and the View menu; only matters while something is playing there.
    @AppStorage("player.theatre") private var playerTheatre = false
    /// The panels as drawers outside the window; see `OuterDrawers`.
    private var drawers: OuterDrawers { .shared }

    var body: some View {
        VStack(spacing: 0) {
            if themedFullScreen { fullScreenBar }
            VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Inline only in full screen, where there is no outside for the drawers to
                // slide into. Everywhere else they come out from behind the window and the
                // page keeps its size.
                SavedChannelsDrawer(model: model)
                    .drawerSlot(open: isFullScreen && model.showChannelsDrawer, side: .leading)

                page

                FamilyDrawer(model: model)
                    .drawerSlot(open: isFullScreen && model.showFamilyDrawer, side: .trailing)
            }

            // Its own module, full width, between the page and the footer: the window
            // grows to make room, so it reads as a unit bolted in rather than something
            // laid over the list.
            if let now = model.nowPlaying {
                NowPlayingMonitor(
                    video: now.video, player: now.player, ratio: now.ratio,
                    analysis: model.trackAnalysis,
                    expand: model.reopenNowPlaying,
                    toNotch: { model.popOutToIsland(tuckingWindowAway: true) },
                    stop: model.stopNowPlaying
                )
                .frame(height: AppModel.nowPlayingHeight - 12)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Palette.ground)
                .overlay(alignment: .top) { Rectangle().fill(Palette.ink(0.10)).frame(height: 1) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let loading = model.nowLoading {
                NowLoadingModule(video: loading, error: model.nowLoadingError,
                                 cancel: model.cancelNowLoading)
                    .frame(height: AppModel.nowPlayingHeight - 12)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Palette.ground)
                    .overlay(alignment: .top) { Rectangle().fill(Palette.ink(0.10)).frame(height: 1) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            }
            // Downloads slides up from the footer, over the page rather than squeezing
            // it, so the player and the list keep their size. Clipped here so it rises
            // out from behind the footer instead of crossing it. Always inside, full
            // screen or not.
            .overlay(alignment: .bottom) {
                if model.showDownloads {
                    DownloadsDrawer(
                        downloader: model.downloader,
                        updater: model.updater,
                        isPresented: $model.showDownloads
                    )
                    .frame(height: Layout.downloadsHeight)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: -2)
                    .transition(.move(edge: .bottom))
                }
            }
            .clipped()

            VersionFooter(updater: model.appUpdater,
                          downloader: model.downloader,
                          downloadsOpen: model.showDownloads,
                          toggleDownloads: model.toggleDownloads,
                          playerOpen: model.preview.video != nil)
        }
        .animation(.easeOut(duration: 0.25), value: model.nowPlaying?.video.id ?? model.nowLoading?.id)
        .frame(minWidth: 820, minHeight: 520)
        // Under everything, up into the title bar: the window otherwise shows AppKit's own
        // grey in the strip between the toolbar and the header — Classic included, once
        // the header is a row of its own under the title bar.
        .background {
            Palette.ground.ignoresSafeArea()
        }
        .animation(Layout.drawerEase, value: model.showChannelsDrawer)
        .animation(Layout.drawerEase, value: model.showFamilyDrawer)
        .animation(Layout.drawerEase, value: model.showDownloads)
        .toolbar(themedFullScreen ? .hidden : .visible, for: .windowToolbar)
        .background(WindowReader { window in
            drawers.attach(to: window)
            syncDrawers()
        })
        .onChange(of: model.showChannelsDrawer) { syncDrawers() }
        .onChange(of: model.showFamilyDrawer) { syncDrawers() }
        .onChange(of: isFullScreen) { syncDrawers() }
        // Read back on appearing as well: a theme change rebuilds this view mid-full-screen.
        .onAppear {
            isFullScreen = NSApp.windows.contains { $0.styleMask.contains(.fullScreen) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        // The title bar is the system's in Classic. A theme paints it in its own ground
        // and swaps the system title for one in its lettering — the grey strip otherwise
        // sits over the whole window like a lid from a different app.
        .toolbarBackground(Palette.ground, for: .windowToolbar)
        .toolbarBackgroundVisibility(isClassic ? .automatic : .visible, for: .windowToolbar)
        .toolbar(removing: isClassic ? nil : .title)
        .toolbar {
            if !isClassic {
                ToolbarItem(placement: .navigation) {
                    Text(Paths.displayName)
                        .displayType(13, classic: .semibold)
                        .foregroundStyle(Palette.ink(0.85))
                        .fixedSize()
                }
            }
            // Always in the title bar, so the row can be brought back from wherever it
            // was hidden. Only once there is a header to hide.
            if collapsed {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(Self.morph) { headerHidden.toggle() }
                    } label: {
                        Image(systemName: headerHidden ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.ink(0.75))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(headerHidden ? "Show the search bar  (⌥⌘F)" : "Hide the search bar  (⌥⌘F)")
                    .accessibilityLabel(headerHidden ? "Show search bar" : "Hide search bar")
                    .pointingHand()
                }
            }
        }
        // Dismissal goes through the model rather than straight at the flag, so closing
        // the sheet also clears whatever one-off answer it was showing.
        .sheet(isPresented: Binding(
            get: { model.appUpdater.isShowingResult },
            set: { if !$0 { model.appUpdater.dismissResult() } }
        )) {
            AppUpdateSheet(updater: model.appUpdater)
                .themedButtons()
        }
        .sheet(isPresented: $model.showPhoneSetup) {
            PhoneSetupSheet(model: model)
                .themedButtons()
        }
        .sheet(isPresented: $model.showDevices, onDismiss: { model.focusedDevice = nil }) {
            DevicesSheet(model: model)
                .themedButtons()
        }
        // The other guardian writes into the shared folder and nothing here is told, so
        // the honest moment to re-read is whenever this window comes back to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.syncShelf() }
        }
        .task { await model.syncShelf() }
        // A few seconds after launch, once the window has settled: read the saved
        // channels ahead of the first click on one.
        // Then every half hour, which reads only those gone stale since.
        .task {
            try? await Task.sleep(for: .seconds(4))
            model.warmSavedChannels()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30 * 60))
                model.warmSavedChannels()
            }
        }
    }

    /// The app itself — hero, then results — in whatever width the panels have left it.
    private var page: some View {
        GeometryReader { geo in
            // One number drives the whole transition: the header's height. The results
            // are offset by exactly that, so they are revealed from underneath as it
            // shrinks rather than being covered by it — one motion, not two.
            let bar = headerHidden ? 0 : Chrome.header
            let headerHeight = collapsed ? bar : geo.size.height
            let resultsHeight = max(geo.size.height - bar, 0)

            ZStack(alignment: .top) {
                resultsArea(width: geo.size.width, height: resultsHeight)
                    .frame(width: geo.size.width, height: resultsHeight)
                    .offset(y: headerHeight)

                header(height: headerHeight)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .animation(Self.morph, value: collapsed)
        // The island is for when the window is put away: minimised, or the app hidden.
        // Minimising should not stop what you are watching, so it goes up there; the
        // window coming back takes it back down, into the Now Playing bar.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willMiniaturizeNotification)) { _ in
            model.popOutToIsland()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willHideNotification)) { _ in
            model.popOutToIsland()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in
            model.windowCameBack()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in
            model.windowCameBack()
        }

        .onReceive(NotificationCenter.default.publisher(for: .openLibrary)) { _ in
            model.drainOpenedLibraries()
        }
        .task {
            // A library double-clicked in the Finder may have arrived before this view
            // existed, so the queue is drained here as well as on the notification.
            model.drainOpenedLibraries()
            // One quiet check per launch: yt-dlp ages out of working every few weeks,
            // and the failure it causes looks like a broken app rather than stale tool.
            await model.updater.refreshCurrent()
            await model.updater.check()
            // And one for the app itself. Quiet too — if there is nothing, nothing is
            // said; if there is, a pill appears in the chrome and waits to be noticed.
            await model.appUpdater.check()
        }
    }

    /// Open or shut the outside drawers to match the model — all shut in full screen,
    /// where the inline slots take over.
    private func syncDrawers() {
        let outside = !isFullScreen
        drawers.sync([
            .saved: outside && model.showChannelsDrawer,
            .family: outside && model.showFamilyDrawer,
        ]) { kind in
            switch kind {
            case .saved: AnyView(SavedChannelsDrawer(model: model))
            case .family: AnyView(FamilyDrawer(model: model))
            }
        }
    }

    // MARK: - Toolbar

    /// Full screen puts the toolbar in a strip of the system's own drawing, which no
    /// toolbar background reaches — it came up AppKit grey over a themed window. So a
    /// theme hides it there and draws this in its place: its lettering, its ground and
    /// its edge.
    private var fullScreenBar: some View {
        HStack(spacing: 8) {
            Text(Paths.displayName)
                .displayType(13, classic: .semibold)
                .foregroundStyle(Palette.ink(0.85))
            Spacer()
        }
        .padding(.horizontal, Layout.gutter)
        .frame(height: 52)
        .background(Palette.ground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.active.edgeTint.opacity(0.35)).frame(height: 1)
        }
    }

    private var themedFullScreen: Bool { isFullScreen && !isClassic }

    /// Always mounted, so its offset can animate. Off-screen below the hero until the
    /// header collapses and lifts it into view.
    ///
    /// The player sits at the top of it, across its full width, with the list below: a
    /// video opened from the list plays above the list it came from, and the next one
    /// clicked replaces it there. See `PreviewPanel`.
    private func resultsArea(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // The seam under the header, in the palette's hairline rather than AppKit's
            // divider grey, which belongs to no theme.
            Rectangle().fill(Palette.ink(0.10)).frame(height: 1)
            PreviewPanel(
                session: model.preview,
                available: height,
                width: width,
                download: { model.downloadPreviewed($0) },
                popOut: { model.popOutToIsland(tuckingWindowAway: true) },
                isSaved: { model.isSaved($0) },
                toggleSaved: { model.toggleSaved($0) },
                dismiss: model.dismissPreview
            )
            // Over the list, so the resize grip on its lower edge can be caught.
            .zIndex(1)
            if playerTheatre && model.preview.video != nil {
                // The player has the page; the list waits underneath for it to come back.
            } else if let error = model.statusError, model.showsResults {
                ErrorBanner(message: error) { model.goHome() }
                Divider()
            }
            if model.showsList {
                // Folded to nothing rather than removed while the player has the page,
                // so the list keeps its place and nothing in it is torn down mid-toggle.
                let folded = playerTheatre && model.preview.video != nil
                Group {
                    switch model.mode {
                    // The saved list is a video list; everything about it is the same view.
                    case .videos, .saved: ResultsList(model: model)
                    case .channels:       ChannelResults(model: model)
                    }
                }
                .frame(maxHeight: folded ? 0 : .infinity)
                .clipped()
                .opacity(folded ? 0 : 1)
                .allowsHitTesting(!folded)
                .accessibilityHidden(folded)
            } else {
                Palette.page
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.preview.video == nil)
        .clipped()
    }

    // MARK: - Header

    private func header(height: CGFloat) -> some View {
        ZStack {
            Palette.ground
            if !collapsed {
                AuroraBackground().transition(.opacity)
            }

            if collapsed {
                // One row under the title bar: whose channel this is, and Home and the
                // panels' switches. No search bar: with a channel open it only repeated
                // the channel's URL, and the badge already says whose it is. A new search
                // is Home (the text is kept), or ⌘L.
                HStack(spacing: 10) {
                    OpenChannelBadge(model: model)
                    // Search turned into Stop while a channel was being read; with the
                    // pill gone from here, Stop sits beside what it would stop.
                    if model.isBusy {
                        Button(action: model.stop) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.chrome())
                        .help(model.mode == .videos
                              ? "Stop reading this channel and keep what has been found"
                              : "Stop searching")
                        .transition(.opacity)
                    }
                    Spacer(minLength: 8)
                    PanelSwitches(model: model, showsHome: true)
                        .matchedGeometryEffect(id: "panels", in: hero)
                }
                .frame(height: Chrome.large)
                .padding(.horizontal, Layout.gutter)
                .frame(maxHeight: .infinity, alignment: .center)
                .animation(.easeOut(duration: 0.15), value: model.isBusy)
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 16) {
                        BrandMark(width: 44)
                            .matchedGeometryEffect(id: "brand", in: hero)
                            // A theme's occasional glint on the mark's corner.
                            .overlay(alignment: .topTrailing) {
                                Glint(seed: 1, size: 22).offset(x: 8, y: -8)
                            }
                        Text(Paths.displayName)
                            .displayType(30)
                            .foregroundStyle(Palette.ink(1))
                            // Wide lettering (Nostromo's, Dune's) runs past the window
                            // at 40pt; it shrinks rather than being cut off.
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            // And on the tip of the last letter.
                            .overlay(alignment: .topTrailing) {
                                Glint(seed: 2, size: 30).offset(x: 12, y: -6)
                            }
                            .transition(.opacity)
                    }
                    SearchPill(model: model, compact: false)
                        .matchedGeometryEffect(id: "pill", in: hero)
                        .frame(maxWidth: 680)
                        .padding(.top, 26)
                    // Under the pill, squared to its two ends: what to type on the left,
                    // where else to go on the right. The switches are the header's, so
                    // they travel up with the page when it collapses. No Home here: this
                    // is home.
                    HStack(alignment: .center, spacing: 12) {
                        statusLine
                        Spacer(minLength: 0)
                        PanelSwitches(model: model, showsHome: false)
                            .matchedGeometryEffect(id: "panels", in: hero)
                    }
                    .frame(maxWidth: 680, minHeight: Chrome.large)
                    // Inset to the pill's rounded ends, so both sides line up with what
                    // is inside it rather than with the curve.
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    // What is going on, before anything has been typed. A search box with
                    // a row of chips under it was not a command centre; this is.
                    if Edition.isFamily { CommandBoard(model: model) }
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)   // sits the block a little above centre
                }
                .padding(.horizontal, 40)
            }
        }
        .frame(height: height)
        .clipped()
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            if model.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Palette.ink(1))
                    Text(model.mode == .videos ? "Reading the channel…" : "Searching channels…")
                }
                .foregroundStyle(Palette.ink(0.75))
            } else if let error = model.statusError {
                Text(error)
                    .foregroundStyle(Palette.onFill)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 480, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.accent.opacity(0.9), in: ThemedRect(cornerRadius: 9))
            } else {
                Text("Paste a channel, or search for one by name.")
                    .foregroundStyle(Palette.ink(0.55))
            }
        }
        .font(.system(size: 13))
        .transition(.opacity)
    }
}

// MARK: - Chrome

/// Home, Saved and Users, in one container — beside the open channel in the header, and
/// under the right end of the search pill on the landing page. Downloads is not here:
/// it rises out of the footer, so its switch is in the footer.
///
/// They have been toolbar buttons, a header cluster, handles on the window's edges (which
/// lay over the list), icons at the end of the search pill, and title-bar buttons. Inside
/// the pill they read as search options; in the title bar they were small and crowded
/// the window's name. Here they are their own labelled group, apart from the search but
/// next to it. The header row can be hidden; ⌘1 / ⌘3 / ⇧⌘H still reach all three.
private struct PanelSwitches: View {
    @Bindable var model: AppModel
    let showsHome: Bool
    /// The chosen switch's plate is one plate, moved: opening Users with Saved open
    /// slides it across rather than lighting one and putting the other out.
    @Namespace private var thumb

    var body: some View {
        let track = ThemedRect(cornerRadius: Chrome.radius(Chrome.large), style: .continuous)
        HStack(spacing: 2) {
            if showsHome {
                Switch(icon: "house", title: "Home", isOn: false,
                       help: "Back to the start — the URL is kept  (⇧⌘H)",
                       thumb: thumb, action: model.goHome)
            }
            Switch(icon: "bookmark", title: "Saved", isOn: model.showChannelsDrawer,
                   help: "\(model.showChannelsDrawer ? "Close" : "Open") Saved  (⌘1)",
                   thumb: thumb, action: model.toggleChannelsDrawer)
            if Edition.isFamily {
                Switch(icon: "person.2", title: "Users", isOn: model.showFamilyDrawer,
                       help: "\(model.showFamilyDrawer ? "Close" : "Open") Users  (⌘3)",
                       thumb: thumb, action: model.toggleFamilyDrawer)
            }
        }
        .padding(Chrome.trackInset)
        .frame(height: Chrome.large)
        // In a theme, built like the search pill above it at rest — the field's fill, its
        // rim and the theme's edge — with the chosen switch's plate in the highlight.
        .background(themed ? Palette.field : Palette.ink(0.05), in: track)
        .overlay { track.strokeBorder(Palette.ink(themed ? 0.10 : 0.09), lineWidth: 1) }
        .themeEdge(track)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.showChannelsDrawer)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.showFamilyDrawer)
        .fixedSize()
    }

    private var themed: Bool { Theme.active.id != .classic }

    private struct Switch: View {
        /// What is chosen is lit in the theme's highlight, where it has one.
        static var chosen: Color { Theme.active.id == .classic ? Palette.accent : Theme.active.litTint }

        let icon: String
        let title: String
        let isOn: Bool
        let help: String
        let thumb: Namespace.ID
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            let shape = ThemedRect(cornerRadius: Chrome.radius(Chrome.large) - Chrome.trackInset,
                                   style: .continuous)
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: isOn ? "\(icon).fill" : icon)
                        .font(.system(size: 11.5, weight: .medium))
                    Text(title)
                        .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                }
                .foregroundStyle(isOn ? Self.chosen : Palette.ink(hovering ? 0.9 : 0.62))
                .padding(.horizontal, 11)
                .frame(maxHeight: .infinity)
                .background {
                    if isOn {
                        let themed = Theme.active.id != .classic
                        // Ring World: the dark armour plate, with only the rim and lettering
                        // in the visor's orange.
                        shape.fill(Theme.active.markOnHighlight
                                   ? (Theme.active.markFill ?? Theme.active.glowDeep)
                                   : themed ? Self.chosen.opacity(0.18) : Palette.ink(0.12))
                            .overlay {
                                if themed { shape.strokeBorder(Self.chosen.opacity(0.7), lineWidth: 1) }
                            }
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    } else if hovering {
                        shape.fill(Palette.ink(0.06))
                    }
                }
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .pointingHand()
        }
    }
}

/// The channel that is open, at the head of the header row: its picture and its name, so
/// the row says whose videos are below before you read the list. Nothing while there is
/// no channel — a search's hits, or the saved videos.
private struct OpenChannelBadge: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.mode == .videos, let channel = shown {
            HStack(spacing: 8) {
                ChannelAvatar(channel: channel, size: 32)
                Text(channel.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 220, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .help(channel.title)
            .transition(.opacity)
        }
    }

    /// The scraped channel once its page has answered; until then, whichever one was
    /// clicked to open it, so the name is there from the first moment.
    private var shown: Channel? {
        // A listing from yt-dlp carries no picture, so a saved copy of the channel — which
        // has one — is preferred, then whichever channel was clicked to open it.
        if var ref = model.scrapedChannel {
            if !model.scraper.channel.isEmpty { ref.title = model.scraper.channel }
            if ref.avatar == nil {
                ref.avatar = (model.library.channels.first { $0.id == ref.id }
                              ?? model.openingChannel)?.avatar
            }
            return ref
        }
        return model.openingChannel
    }
}

/// The search pill's Videos / Shorts / Live / Music choice, for a themed window.
private struct TabChooser: View {
    @Binding var tab: ChannelTab
    let compact: Bool
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Text(tab.label)
                    .font(.system(size: compact ? 12 : 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                    .foregroundStyle(Palette.fieldInk.opacity(0.55))
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .foregroundStyle(Palette.fieldInk)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(maxHeight: .infinity)
            .background(Palette.fieldRaised, in: ThemedCapsule())
            .contentShape(ThemedCapsule())
        }
        .buttonStyle(.plain)
        .help("Which tab of the channel to list")
        .pointingHand()
        .animation(.easeOut(duration: 0.15), value: open)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ChannelTab.allCases) { option in
                    Row(option: option, isOn: option == tab) {
                        tab = option
                        open = false
                    }
                }
            }
            .padding(6)
            .frame(width: 150)
            .themeEdge(radius: 10)
            .presentationBackground(Palette.surface)
        }
    }

    private struct Row: View {
        let option: ChannelTab
        let isOn: Bool
        let pick: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: pick) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(isOn ? 1 : 0)
                    Text(option.label)
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(hovering ? Palette.onFill : (isOn ? Palette.accent : Palette.ink(0.9)))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(hovering ? Palette.accent : .clear,
                            in: ThemedRect(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

/// The one rounded bar holding the URL field, the tab menu and Scrape. It is the same
/// view in both states — that is what lets it travel rather than cut.
private struct SearchPill: View {
    @Bindable var model: AppModel
    let compact: Bool
    /// The same full-size pill, in the collapsed header rather than on the hero: a lighter
    /// shadow, since it is one control among several, and it does not take focus.
    var inHeader = false
    @FocusState private var focused: Bool

    /// The compact pill is exactly the header's control height, and everything inside it
    /// is that less its 3pt rim — so the tab menu and Search sit in it concentrically, as
    /// parts of one control, rather than as buttons of their own size dropped into a field.
    private var inner: CGFloat { Chrome.large - 6 }

    /// The tab menu only says something when there is a channel to list: it does nothing
    /// for a name search, so it waits until a link or @handle is typed. And never in the
    /// header, where the results toolbar directly below already has the same four tabs —
    /// two controls for one choice could disagree.
    private var showsScope: Bool { model.intent == .scrape && !inHeader }

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            HStack(spacing: compact ? 7 : 10) {
                // A search field says so before anything is typed in it.
                Image(systemName: "magnifyingglass")
                    .font(.system(size: compact ? 11.5 : 14, weight: .medium))
                    .foregroundStyle(Palette.fieldInk.opacity(0.45))
                ZStack(alignment: .leading) {
                    if model.urlText.isEmpty {
                        // Shorter in the header, which shares its row with Home and the
                        // channel's name; cut off, the long one lost the half about names.
                        Text(inHeader ? "Channel link, @handle, or a name"
                                      : "Paste a channel URL or @handle — or type a name to search")
                            .foregroundStyle(Palette.fieldInk.opacity(0.42))
                            .lineLimit(1)
                    }
                    TextField("", text: $model.urlText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Palette.fieldInk)
                        .tint(Palette.accent)
                        .focused($focused)
                        .onSubmit { model.submit() }
                }
            }
            .font(.system(size: compact ? 13 : 14))
            .padding(.leading, compact ? 11 : 18)

            if showsScope, Theme.active.id == .classic {
                Menu {
                    Picker("Type", selection: $model.tab) {
                        ForEach(ChannelTab.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    // The borderless style draws no indicator over a custom background, and
                    // it renders only a single Text — an HStack label comes out blank. So
                    // the chevron is concatenated in, and each run carries its own colour
                    // because a foregroundStyle on the Menu does not reach inside.
                    Text(model.tab.label)
                        .font(.system(size: compact ? 12 : 13, weight: .medium))
                        .foregroundStyle(Palette.fieldInk)
                        + Text("  ")
                        + Text(Image(systemName: "chevron.down"))
                        .font(.system(size: compact ? 8 : 9, weight: .bold))
                        .foregroundStyle(Palette.fieldInk.opacity(0.55))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.horizontal, compact ? 10 : 12)
                .frame(height: compact ? inner : 34)
                .background(Palette.fieldRaised, in: ThemedCapsule())
                .help("Which tab of the channel to list")
                .pointingHand()
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            } else if showsScope {
                // A theme cannot reach inside a native menu, so it gets a picker of its
                // own — same choices, in the theme's lettering and edge.
                TabChooser(tab: $model.tab, compact: compact)
                    .frame(height: compact ? inner : 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }

            Button {
                model.isBusy ? model.stop() : model.submit()
            } label: {
                // The label is the answer to "what will return do with what I have
                // typed?", so it has to track the field rather than sit on one word.
                // Not ready is a neutral outline, not a faded accent: pink read as a softer
                // action rather than one waiting for a URL. An outline rather than a
                // filled plate, so an empty Search is not the heaviest thing in the pill.
                let ready = model.canScrape || model.isBusy
                // The mark's treatment where the theme gives its primary controls one: a
                // dark plate rimmed and lettered in the highlight, not a bright fill.
                let marked = Theme.active.markOnHighlight
                let plate = Theme.active.markFill ?? Theme.active.glowDeep
                Text(buttonLabel)
                    .font(.system(size: compact ? 12.5 : 14, weight: .semibold))
                    .foregroundStyle(ready ? (marked ? Theme.active.litTint : Palette.onFill)
                                     : Palette.fieldInk.opacity(0.42))
                    // Stop and Search both fit today. The frame is fixed, so anything
                    // longer would wrap inside the capsule rather than overflow it —
                    // truncating is the failure worth having.
                    .lineLimit(1)
                    .frame(width: compact ? 70 : 84, height: compact ? inner : 38)
                    .background(ready ? (marked ? plate : Palette.accent) : .clear, in: ThemedCapsule())
                    .overlay {
                        if !ready {
                            ThemedCapsule().strokeBorder(Palette.fieldInk.opacity(0.16), lineWidth: 1.5)
                        } else if marked {
                            ThemedCapsule().strokeBorder(Theme.active.litTint.opacity(0.9), lineWidth: 1)
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: ready)
            }
            .buttonStyle(.plain)
            .disabled(!model.canScrape && !model.isBusy)
            .keyboardShortcut(.return, modifiers: [])
            .help(helpText)
            .pointingHand()
        }
        // The scope arriving moves Search along; animated, so it slides rather than jumps.
        .animation(.easeOut(duration: 0.18), value: showsScope)
        .padding(compact ? 3 : 7)
        .frame(height: compact ? Chrome.large : nil)
        .background(Palette.field, in: ThemedCapsule())
        .overlay(ThemedCapsule().strokeBorder(Palette.ink(0.10), lineWidth: 1))
        .themeEdge(ThemedCapsule(), lit: focused)
        // A contact shadow in the header, where the pill is one control among several; the
        // deep one only on the hero, where it is the whole page.
        .shadow(color: .black.opacity(compact || inHeader ? 0.18 : 0.35),
                radius: compact || inHeader ? 6 : 22, y: compact || inHeader ? 2 : 8)
        // Landing on the hero, the one thing to do is type a URL.
        .onAppear { if !compact && !inHeader { focused = true } }
    }

    /// "Search" whether the field holds a name or a channel's URL: opening a channel
    /// reads its kept list and asks YouTube only for what is new, which is a search in
    /// every sense the person pressing it cares about. The help text still says which.
    private var buttonLabel: String {
        model.isBusy ? "Stop" : "Search"
    }

    private var helpText: String {
        if model.isBusy {
            return model.mode == .videos
                ? "Stop reading this channel and keep what has been found"
                : "Stop searching"
        }
        return model.intent == .search
            ? "Find channels called “\(model.urlText.trimmingCharacters(in: .whitespaces))”  (↩)"
            : "List this channel's \(model.tab.label.lowercased())  (↩)"
    }
}

private struct ErrorBanner: View {
    let message: String
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warn)
            Text(message).font(.system(size: 12)).lineLimit(2)
            Spacer(minLength: 8)
            Button("Start over", action: reset)
                .controlSize(.small)
                .help("Go back to the start, keeping the URL you typed")
                .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.warn.opacity(0.12))
    }
}

// MARK: - Results

private struct ResultsList: View {
    @Bindable var model: AppModel

    /// Where the page being fetched will start, held while it loads so the list can be
    /// taken to it once it lands.
    ///
    /// Without this, loading more looks like it did nothing: you are at the foot of the
    /// list when you press the button, the new rows are appended *below* the viewport,
    /// and the pixels in front of you do not change.
    @State private var nextPageAnchor: Int?

    var body: some View {
        VStack(spacing: 0) {
            ResultsToolbar(model: model)
            ScrollViewReader { proxy in
            ScrollView {
                // Cards, not list rows — they need the gap to read as separate surfaces.
                LazyVStack(spacing: 10) {
                    // Nothing of the new list has landed yet, so its shape stands in for
                    // it. The alternative — an empty page — is the landing screen, and
                    // being sent back there is not what asking for a channel meant.
                    if model.isLoadingList {
                        VideoListSkeleton()
                    } else {
                        rows
                        foot
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 22)
                .animation(.easeOut(duration: 0.24), value: model.keptVisible.count)
            }
            .background(Palette.page)
            // Once the page has settled, put its first row at the top: that is what
            // "load 25 more" is asking for, and it is the only way the result of
            // pressing it is visible from where you pressed it.
            .onChange(of: model.scraper.isBusy) { _, busy in
                guard !busy, let anchor = nextPageAnchor else { return }
                nextPageAnchor = nil
                guard anchor < model.scraper.videos.count else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo(model.scraper.videos[anchor].id, anchor: .top)
                }
            }
            }
        }
    }

    /// Kept first, under a heading — a row that jumps the queue should say why it is
    /// there rather than leave you wondering whether the channel's order is broken.
    @ViewBuilder
    private var rows: some View {
        if !model.keptVisible.isEmpty {
            GroupLabel(text: "Kept from this channel", accented: true)
            ForEach(model.keptVisible) { row($0) }
            if !model.restVisible.isEmpty {
                GroupLabel(text: "All videos")
            }
        }
        ForEach(model.restVisible) { row($0) }
    }

    /// What the foot of the list offers: the next page, or the reason there isn't one.
    @ViewBuilder
    private var foot: some View {
        if model.mode == .saved {
            if model.visible.isEmpty {
                Text(model.filterText.isEmpty
                     ? "No saved videos yet — star one in any channel's list."
                     : "Nothing matches “\(model.filterText)”.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 40)
            }
        } else if model.scraper.isBusy {
            // Checked before the button, because the button unmounts the moment the next
            // page starts — leaving the foot of the list blank for the whole fetch if
            // nothing takes its place. Only ever the next page: a scrape with nothing on
            // screen yet is the skeleton's, not this line's.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the next \(Scraper.pageSize)…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 18)
        } else if model.scraper.canLoadMore && model.filterText.isEmpty {
            Button("Load 25 more") {
                nextPageAnchor = model.scraper.videos.count
                model.scraper.loadMore()
            }
            .controlSize(.large)
            .padding(.vertical, 10)
            .help("Read the next 25 videos from this channel")
            .pointingHand()
        } else if model.visible.isEmpty {
            Text("Nothing matches “\(model.filterText)”.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 40)
        }
    }

    private func row(_ video: Video) -> some View {
        VideoRow(
            video: video,
            isPicked: model.picked.contains(video.id),
            isSaved: model.isSaved(video),
            inSavedList: model.mode == .saved,
            toggle: { model.toggle(video) },
            downloadOne: { model.download([video]) },
            preview: { model.openCard(video) },
            openCard: { model.openCard(video) },
            toggleSaved: { model.toggleSaved(video) },
            shelfMenu: Edition.isFamily ? ShelfMenu(model: model, video: video) : nil
        )
        .id(video.id)
    }
}


// MARK: - Results toolbar

/// Everything that acts on the list, in one toolbar over it: the channel's tabs and its
/// Refresh, the selection, the filter, what is listed, and the download.
///
/// These were two rows — a tab bar of accent capsules and a controls row of grey ones —
/// stacked under the header, so an open channel spent three bands of chrome before its
/// first video. Most windows are wide enough for one row, and get one. A narrow one (the
/// 820pt minimum, or any width with a panel open) gets the same controls in two rows, in
/// the same order, rather than having them squeezed until labels break: `ViewThatFits`
/// tries the single row at its ideal width and falls back.
///
/// Every control is the window's 28pt plate (`ChromeButtonStyle`) and the tabs are one
/// segmented track, so the row reads by what its controls say rather than by their shapes.
/// The accent is spent once: on Download, and only when there is something ticked for it.
private struct ResultsToolbar: View {
    @Bindable var model: AppModel

    /// Only an open channel has tabs, and only a channel can be refreshed.
    private var hasTabs: Bool { model.mode == .videos && model.scraper.rawURL != nil }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                navigation
                if hasTabs || model.searchToReturnTo != nil { ChromeSeparator() }
                selection
                status(withRefreshLine: true)
                if hasTabs { refreshButton }
                actions
            }
            .frame(height: Chrome.bar)

            VStack(spacing: 0) {
                if hasTabs || model.searchToReturnTo != nil {
                    HStack(spacing: 8) {
                        navigation
                        Spacer(minLength: 8)
                        if hasTabs {
                            RefreshLine(scraper: model.scraper)
                            refreshButton
                        }
                    }
                    .frame(height: Chrome.bar)
                }
                HStack(spacing: 8) {
                    selection
                    status(withRefreshLine: false)
                    actions
                }
                .frame(height: Chrome.bar)
            }
        }
        .padding(.horizontal, Layout.gutter)
        .chromeBar()
    }

    /// Where the list is: back to the search it came from, and which of the channel's tabs.
    @ViewBuilder
    private var navigation: some View {
        // First, because it is the only control here that leaves the list rather than
        // acting on it. Named after what you searched for: "Back" alone makes you
        // remember, and remembering is the thing that was missing.
        if let query = model.searchToReturnTo {
            Button {
                model.returnToSearch()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text(query)
                        .truncationMode(.tail)
                        .frame(maxWidth: 140)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.chrome())
            .help("Back to the results for “" + query + "” (⌘[)")
            .keyboardShortcut("[", modifiers: .command)
            .transition(.opacity)
        }

        // The type used to be chosen only in the search pill, before scraping — switching
        // meant changing the menu and scraping again. Here it is a tab on the channel
        // itself, and since each tab is kept (`ListingCache`), going back to one already
        // read is instant.
        if hasTabs {
            ChromeSegmented(
                options: ChannelTab.allCases,
                selection: model.scraper.tab,
                label: { $0.label },
                help: { "This channel's \($0.label.lowercased())" },
                pick: { model.showTab($0) }
            )
        }
    }

    /// What is picked and which rows are shown.
    @ViewBuilder
    private var selection: some View {
        Button {
            model.toggleAllVisible()
        } label: {
            HStack(spacing: 7) {
                CheckBox(isOn: model.allVisiblePicked, size: 14)
                Text("Select all")
            }
        }
        .buttonStyle(.chrome())
        .help(model.allVisiblePicked
              ? "Untick every video currently listed"
              : "Tick every video currently listed")

        // Was a hard 150. A fixed width in a row that has to fit a narrow window means
        // the squeeze lands somewhere else — on the labels either side, which then broke
        // mid-word. The ideal is what the single-row layout is measured at.
        ChromeField(icon: "line.3.horizontal.decrease", prompt: "Filter titles",
                    text: $model.filterText)
            .frame(minWidth: 80, idealWidth: 130, maxWidth: 170)

        // Sits against the count, so it reads as keeping the channel rather than anything
        // to do with the selection.
        if model.mode != .saved, let channel = model.scrapedChannel {
            SaveMark(
                isSaved: model.library.contains(channel.id),
                size: 14,
                action: { model.toggleSaved(channel) }
            )
        }
    }

    /// The readout: how many, how many picked, and — on the single row — how fresh.
    ///
    /// The row's designated victim. Everything else is a control with a fixed label; this
    /// is the only part that can lose characters and still make sense, so it is the only
    /// part allowed to, and its small ideal width is what lets the single row be chosen
    /// whenever the controls themselves fit.
    private func status(withRefreshLine: Bool) -> some View {
        HStack(spacing: 6) {
            if model.scraper.isBusy && !model.isLoadingList {
                ProgressView().controlSize(.mini)
            }
            Text(countText)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(countText)
                .layoutPriority(1)
            if withRefreshLine && hasTabs {
                RefreshLine(scraper: model.scraper, leadingDot: true)
            }
        }
        .font(.system(size: 11.5).monospacedDigit())
        .foregroundStyle(Palette.ink(0.55))
        .padding(.leading, 4)
        .frame(minWidth: 0, idealWidth: 72, maxWidth: .infinity, alignment: .leading)
    }

    /// Reads only the newest videos onto the kept list; the line beside it says how old
    /// the list is, because it no longer re-reads itself on every open.
    private var refreshButton: some View {
        Button {
            model.refreshListing()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.chrome(square: true))
        .disabled(!model.scraper.canRefresh)
        .keyboardShortcut("r", modifiers: .command)
        .help("Look for new videos on this tab  (⌘R)")
        .accessibilityLabel("Refresh")
    }

    /// Quality and Download sit with the list they act on, the way the web app's results
    /// bar had them. The mp3 sits under the qualities rather than among them because it is
    /// not one of them: every quality above is a choice of one file, and this asks for a
    /// second one alongside whichever was chosen.
    @ViewBuilder
    private var actions: some View {
        QualityMenu(
            quality: $model.quality,
            alsoAudio: $model.alsoAudio,
            face: model.formatLabel
        )
        .help(model.quality.isAudioOnly
              ? "Which quality to fetch for the videos you pick"
              : "Which quality to fetch for the videos you pick, and whether to keep an mp3 beside each one")

        Button {
            model.downloadPicked()
        } label: {
            Label(model.picked.isEmpty ? "Download" : "Download \(model.picked.count)",
                  systemImage: "arrow.down")
                .monospacedDigit()
        }
        .buttonStyle(.chrome(.primary))
        .disabled(model.picked.isEmpty)
        .keyboardShortcut("d", modifiers: .command)
        .help(model.picked.isEmpty
              ? "Tick some videos first, then download them here"
              : "Download the \(model.picked.count) ticked video\(model.picked.count == 1 ? "" : "s") at \(model.formatLabel)  (⌘D)")
    }

    private var countText: String {
        // While the list is still coming there is nothing to count, and "0 videos" over a
        // page of skeletons reads as an answer rather than a wait. The channel's name is
        // not repeated here: the header's badge carries it, from the first moment.
        if model.isLoadingList { return "Reading the channel…" }
        let total = model.listedVideos.count
        let shown = model.visible.count
        var parts: [String] = []
        if model.mode == .saved { parts.append("Saved videos") }
        // A kept video can come from beyond what has been loaded, which would otherwise
        // read as "26 of 25". The count describes the channel's listing; the kept ones
        // are reported as their own fact.
        parts.append(shown >= total
                     ? "\(total) video\(total == 1 ? "" : "s")"
                     : "\(shown) of \(total)")
        if !model.keptVisible.isEmpty { parts.append("\(model.keptVisible.count) kept") }
        if !model.picked.isEmpty { parts.append("\(model.picked.count) selected") }
        return parts.joined(separator: "  ·  ")
    }
}

/// "Updated 16 minutes ago · 3 new videos", or that a refresh is under way.
private struct RefreshLine: View {
    let scraper: Scraper
    /// On the single row it follows the count, and takes the count's separator.
    var leadingDot = false

    var body: some View {
        Group {
            if scraper.isRefreshing {
                Text(prefix + "Checking for new videos…")
            } else if let refreshed = scraper.refreshed {
                // Re-drawn each minute so "just now" moves on.
                TimelineView(.everyMinute) { _ in
                    Text(prefix + Self.updated(refreshed) + Self.added(scraper.added))
                }
            }
        }
        .font(.system(size: 11.5).monospacedDigit())
        .foregroundStyle(Palette.ink(0.5))
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var prefix: String { leadingDot ? "·  " : "" }

    private static func updated(_ date: Date) -> String {
        if Date.now.timeIntervalSince(date) < 60 { return "Updated just now" }
        return "Updated " + date.formatted(.relative(presentation: .named))
    }

    private static func added(_ count: Int?) -> String {
        switch count {
        case nil: ""
        case 0?: "  ·  nothing new"
        case 1?: "  ·  1 new video"
        case let n?: "  ·  \(n) new videos"
        }
    }
}


// MARK: - Channel results

/// What a search puts in the results area, in place of the video list.
private struct ChannelResults: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            controls
            ScrollView {
                LazyVStack(spacing: 10) {
                    if model.isLoadingList {
                        ChannelListSkeleton()
                    }
                    ForEach(model.search.results) { channel in
                        ChannelRow(
                            channel: channel,
                            isSaved: model.library.contains(channel.id),
                            open: { model.open(channel) },
                            toggleSaved: { model.toggleSaved(channel) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 22)
            }
            .background(Palette.page)
        }
    }

    /// The same toolbar band as a channel's list, so moving between a search and a
    /// channel changes what the bar says and not where it is or how tall.
    private var controls: some View {
        HStack(spacing: 8) {
            Text("Channels matching “\(model.search.query)”")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.ink(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(model.isLoadingList ? "Searching…" : "\(model.search.results.count)")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(Palette.ink(0.55))

            Spacer(minLength: 12)

            if model.search.isBusy {
                ProgressView().controlSize(.mini)
            }

            Text("Bookmark a channel to keep it in the side panel")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink(0.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
        }
        .padding(.horizontal, Layout.gutter)
        .frame(height: Chrome.bar)
        .chromeBar()
    }
}


/// The one-line heading over each half of a channel's list. Small capitals with a little
/// tracking, as a section label on an instrument is: it names a group and is not one more
/// line of content to read.
private struct GroupLabel: View {
    let text: String
    var accented = false

    var body: some View {
        HStack(spacing: 6) {
            if accented {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.accent)
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Palette.ink(0.5))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, accented ? 0 : 10)
    }
}
