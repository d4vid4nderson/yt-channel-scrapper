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
    /// The window's width and the toolbar title's, measured, so the search pill in the
    /// toolbar can be given exactly the room between them. A toolbar item that asks for
    /// more than there is gets moved, with everything after it, into the » overflow menu.
    @State private var windowWidth: CGFloat = 1000
    @State private var titleWidth: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            if themedFullScreen { fullScreenBar }
            HStack(spacing: 0) {
                SavedChannelsDrawer(model: model)
                    .drawerSlot(open: model.showChannelsDrawer, side: .leading)

                VStack(spacing: 0) {
                    page
                    DownloadsDrawer(
                        downloader: model.downloader,
                        updater: model.updater,
                        isPresented: $model.showDownloads
                    )
                    .bottomDrawerSlot(open: model.showDownloads)
                }

                FamilyDrawer(model: model)
                    .drawerSlot(open: model.showFamilyDrawer, side: .trailing)
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

            VersionFooter(updater: model.appUpdater)
        }
        .animation(.easeOut(duration: 0.25), value: model.nowPlaying?.video.id ?? model.nowLoading?.id)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { windowWidth = $0 }
        .frame(minWidth: 820, minHeight: 520)
        // Under everything, up into the title bar: a theme's window otherwise shows AppKit's
        // own grey in the strip between the toolbar and the header.
        .background {
            if !isClassic { Palette.ground.ignoresSafeArea() }
        }
        .animation(Layout.drawerEase, value: model.showChannelsDrawer)
        .animation(Layout.drawerEase, value: model.showFamilyDrawer)
        .animation(Layout.drawerEase, value: model.showDownloads)
        .toolbar { chrome }
        .toolbar(themedFullScreen ? .hidden : .visible, for: .windowToolbar)
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
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) {
                            titleWidth = $0
                        }
                }
            }
            // Once the hero has collapsed, the search lives here, in one row with the
            // title and the panel buttons, rather than in a band of its own under them.
            // Leading, straight after the title, not centred: a centred item has to fit
            // twice over the wider of its two sides, and spilled onto the title.
            if collapsed {
                if #available(macOS 26, *) {
                    ToolbarItem(placement: .navigation) { toolbarPill }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .navigation) { toolbarPill }
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
            // Collapsed, the header is nothing at all: the search pill has gone up into the
            // window's toolbar, level with the title and the panel buttons.
            let headerHeight = collapsed ? 0 : geo.size.height

            ZStack(alignment: .top) {
                resultsArea(height: geo.size.height)
                    .frame(width: geo.size.width, height: geo.size.height)
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

    // MARK: - Toolbar

    /// The three panels live on the window's own chrome, in one cluster at the trailing
    /// end: left, bottom, right, in the order their edges sit around the window.
    ///
    /// Together rather than split across the bar, because they are one set of controls
    /// doing one kind of thing — a button on each end would read as two unrelated things
    /// rather than three views of what you have kept.
    ///
    /// The icon is a picture of the window with that panel out, so each button says which
    /// edge it opens without a word on it — and a toggle rather than a plain button, so a
    /// lit one is a panel that is open, and pressing it again is how you put it away.
    @ToolbarContentBuilder
    private var chrome: some ToolbarContent {
        // The system title used to be what pushed this cluster to the trailing end. A
        // theme swaps that title for its own, so the gap has to be asked for.
        if #available(macOS 26, *), !isClassic {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            panelToggles
        }
    }

    private var toolbarPill: some View {
        // Room to give way, down to a field and its button: a toolbar item that cannot
        // shrink to fit is moved, with everything after it, into the » overflow menu.
        // Narrow, the type menu goes — the tabs over the channel's list cover it.
        SearchPill(model: model, compact: true, showsType: pillWidth >= 360)
            .frame(minWidth: 170, idealWidth: pillWidth, maxWidth: pillWidth)
            // Clear of the title; a theme's corner brackets reach a few points out.
            .padding(.leading, 12)
    }

    /// What is left of the toolbar row once the traffic lights, the title and the four
    /// panel buttons have theirs, less some air either side.
    private var pillWidth: CGFloat {
        let lights: CGFloat = 80
        let buttons: CGFloat = 4 * 40 + 24
        let air: CGFloat = 84
        return min(max(windowWidth - lights - titleWidth - buttons - air, 170), 1000)
    }

    /// The three panel buttons: in the window toolbar, or in `fullScreenBar` when a
    /// theme has taken the toolbar down in full screen.
    @ViewBuilder
    private var panelToggles: some View {
            // Only once there is somewhere to come back from; on the landing view it
            // would be a button that does nothing.
            if collapsed {
                PanelToggle(
                    icon: "house.fill",
                    title: "Home",
                    isOn: false,
                    help: "Back to the start — the URL is kept  (⇧⌘H)",
                    toggle: model.goHome
                )
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
            PanelToggle(
                icon: "bookmark.fill",
                title: "Saved",
                isOn: model.showChannelsDrawer,
                help: "The channels and videos you have saved  (⌘1)",
                toggle: model.toggleChannelsDrawer
            )
            PanelToggle(
                icon: "arrow.down.circle.fill",
                title: "Downloads",
                // A dot, not a tally: that something is running is the part worth a mark
                // on the chrome, and the panel one click away has the numbers.
                busy: model.downloader.activeCount > 0,
                isOn: model.showDownloads,
                help: "What is downloading, and where it went  (⌘2)",
                toggle: model.toggleDownloads
            )
            PanelToggle(
                icon: "person.2.fill",
                title: "Family",
                isOn: model.showFamilyDrawer,
                help: "Who you can send videos to  (⌘3)",
                toggle: model.toggleFamilyDrawer
            )
    }

    /// Full screen puts the toolbar in a strip of the system's own drawing, which no
    /// toolbar background reaches — it came up AppKit grey over a themed window. So a
    /// theme hides it there and draws this in its place: its lettering, the same three
    /// buttons, its ground and its edge.
    private var fullScreenBar: some View {
        HStack(spacing: 8) {
            Text(Paths.displayName)
                .displayType(13, classic: .semibold)
                .foregroundStyle(Palette.ink(0.85))
            Spacer()
            if collapsed {
                toolbarPill
                Spacer()
            }
            panelToggles
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
    private func resultsArea(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Divider()
            PreviewPanel(
                session: model.preview,
                available: height,
                download: { model.downloadPreviewed($0) },
                popOut: { model.popOutToIsland(tuckingWindowAway: true) },
                isSaved: { model.isSaved($0) },
                toggleSaved: { model.toggleSaved($0) },
                dismiss: model.dismissPreview
            )
            if let error = model.statusError, model.showsResults {
                ErrorBanner(message: error) { model.goHome() }
                Divider()
            }
            if model.showsList {
                switch model.mode {
                // The saved list is a video list; everything about it is the same view.
                case .videos, .saved: ResultsList(model: model)
                case .channels:       ChannelResults(model: model)
                }
            } else {
                Palette.page
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.preview.video == nil)
    }

    // MARK: - Header

    private func header(height: CGFloat) -> some View {
        ZStack {
            Palette.ground
            if !collapsed {
                AuroraBackground().transition(.opacity)
            }

            if !collapsed {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 16) {
                        BrandMark(width: 44)
                            .matchedGeometryEffect(id: "brand", in: hero)
                        Text(Paths.displayName)
                            .displayType(30)
                            .foregroundStyle(Palette.ink(1))
                            // Wide lettering (Nostromo's, Dune's) runs past the window
                            // at 40pt; it shrinks rather than being cut off.
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .transition(.opacity)
                    }
                    SearchPill(model: model, compact: false)
                        .matchedGeometryEffect(id: "pill", in: hero)
                        .frame(maxWidth: 680)
                        .padding(.top, 26)
                    statusLine
                    // What is going on, before anything has been typed. A search box with
                    // a row of chips under it was not a command centre; this is.
                    CommandBoard(model: model)
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
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.accent.opacity(0.9), in: ThemedRect(cornerRadius: 9))
            } else {
                Text("Paste a channel, or search for one by name.")
                    .foregroundStyle(Palette.ink(0.55))
            }
        }
        .font(.system(size: 13))
        .padding(.top, 14)
        .frame(height: 38, alignment: .top)
        .transition(.opacity)
    }
}

// MARK: - Chrome

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
            .padding(.vertical, compact ? 5 : 8)
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
    /// Off in a narrow toolbar, where the field needs the width more.
    var showsType = true
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            ZStack(alignment: .leading) {
                if model.urlText.isEmpty {
                    Text("Paste a channel URL or @handle — or type a name to search")
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
            .font(.system(size: compact ? 13 : 14))
            .padding(.leading, compact ? 14 : 18)

            if !showsType {
                EmptyView()
            } else if Theme.active.id == .classic {
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
                .padding(.vertical, compact ? 5 : 8)
                .background(Palette.fieldRaised, in: ThemedCapsule())
                .help("Which tab of the channel to list")
                .pointingHand()
            } else {
                // A theme cannot reach inside a native menu, so it gets a picker of its
                // own — same choices, in the theme's lettering and edge.
                TabChooser(tab: $model.tab, compact: compact)
            }

            Button {
                model.isBusy ? model.stop() : model.submit()
            } label: {
                // The label is the answer to "what will return do with what I have
                // typed?", so it has to track the field rather than sit on one word.
                Text(buttonLabel)
                    .font(.system(size: compact ? 12.5 : 14, weight: .semibold))
                    .foregroundStyle(Palette.onFill)
                    // Stop/Search/Scrape all fit today. The frame is fixed, so anything
                    // longer would wrap inside the capsule rather than overflow it —
                    // truncating is the failure worth having.
                    .lineLimit(1)
                    .frame(width: compact ? 66 : 78)
                    .padding(.vertical, compact ? 7 : 10)
                    .background(
                        Palette.accent.opacity(model.canScrape || model.isBusy ? 1 : 0.45),
                        in: ThemedCapsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.canScrape && !model.isBusy)
            .keyboardShortcut(.return, modifiers: [])
            .help(helpText)
            .pointingHand()
        }
        .padding(compact ? 5 : 7)
        .background(Palette.field, in: ThemedCapsule())
        .overlay(ThemedCapsule().strokeBorder(Palette.ink(0.10), lineWidth: 1))
        .themeEdge(ThemedCapsule(), lit: focused)
        .shadow(color: .black.opacity(compact ? 0.2 : 0.35), radius: compact ? 8 : 22, y: compact ? 3 : 8)
        // Landing on the hero, the one thing to do is type a URL.
        .onAppear { if !compact { focused = true } }
    }

    private var buttonLabel: String {
        if model.isBusy { return "Stop" }
        return model.intent == .search ? "Search" : "Scrape"
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
            if model.mode == .videos, model.scraper.rawURL != nil {
                ChannelTabBar(model: model)
                Divider()
            }
            controls
            Divider()
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
            shelfMenu: ShelfMenu(model: model, video: video)
        )
        .id(video.id)
    }

    private var controls: some View {
        HStack(spacing: 10) {
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
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 140)
                    }
                    .chip()
                }
                .buttonStyle(.plain)
                .help("Back to the results for “" + query + "” (⌘[)")
                .keyboardShortcut("[", modifiers: .command)
                .pointingHand()
                .transition(.opacity)
            }

            Button {
                model.toggleAllVisible()
            } label: {
                HStack(spacing: 8) {
                    CheckBox(isOn: model.allVisiblePicked, size: 15)
                    Text("Select all")
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .chip(active: model.allVisiblePicked)
            }
            .buttonStyle(.plain)
            .help(model.allVisiblePicked
                  ? "Untick every video currently listed"
                  : "Tick every video currently listed")
            .pointingHand()

            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField("Filter titles…", text: $model.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    // Was a hard 150. A fixed width in a row that has to fit a narrow
                    // window means the squeeze lands somewhere else — on the labels
                    // either side, which then broke mid-word.
                    .frame(minWidth: 70, idealWidth: 150, maxWidth: 150)
            }
            .chip()

            // Sits against the channel's name in the count line, so it reads as
            // keeping the channel rather than anything to do with the selection.
            if model.mode != .saved, let channel = model.scrapedChannel {
                SaveMark(
                    isSaved: model.library.contains(channel.id),
                    size: 14,
                    action: { model.toggleSaved(channel) }
                )
            }

            Text(countText)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
                // The row's designated victim. Everything else is a control with a fixed
                // label; this is the only part that can lose characters and still make
                // sense, so it is the only part allowed to.
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
                .help(countText)

            Spacer(minLength: 12)

            if model.scraper.isBusy {
                ProgressView().controlSize(.small)
            }

            // Quality and Download sit with the list they act on, the way the web app's
            // results bar had them, now that there is no window toolbar.
            // The mp3 sits under the qualities rather than among them because it is not
            // one of them: every quality above is a choice of one file, and this asks for
            // a second one alongside whichever was chosen.
            QualityMenu(
                quality: $model.quality,
                alsoAudio: $model.alsoAudio,
                face: model.formatLabel
            )
            .help(model.quality.isAudioOnly
                  ? "Which quality to fetch for the videos you pick"
                  : "Which quality to fetch for the videos you pick, and whether to keep an mp3 beside each one")
            .pointingHand()

            Button {
                model.downloadPicked()
            } label: {
                Text(model.picked.isEmpty ? "Download" : "Download \(model.picked.count)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.onFill)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Palette.accent.opacity(model.picked.isEmpty ? 0.4 : 1),
                        in: ThemedCapsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.picked.isEmpty)
            .keyboardShortcut("d", modifiers: .command)
            .help(model.picked.isEmpty
                  ? "Tick some videos first, then download them here"
                  : "Download the \(model.picked.count) ticked video\(model.picked.count == 1 ? "" : "s") at \(model.formatLabel)  (⌘D)")
            .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var countText: String {
        // While the list is still coming there is nothing to count, and "0 videos" over a
        // page of skeletons reads as an answer rather than a wait. The channel's name is
        // the useful thing to hold there — it is what you clicked.
        if model.isLoadingList {
            guard let name = model.loadingChannelName else { return "Reading the channel…" }
            return "\(name)  ·  Reading the channel…"
        }
        let total = model.listedVideos.count
        let shown = model.visible.count
        var parts: [String] = []
        if model.mode == .saved {
            parts.append("Saved videos")
        } else if !model.scraper.channel.isEmpty {
            parts.append(model.scraper.channel)
        }
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


// MARK: - Channel tabs

/// Videos / Shorts / Live / Music across the top of an open channel, and the Refresh that
/// goes with them.
///
/// The type used to be chosen only in the search pill, before scraping — switching meant
/// changing the menu and scraping again. Here it is a tab on the channel itself, and since
/// each tab is kept (`ListingCache`), going back to one already read is instant. Refresh
/// reads only the newest videos onto the kept list; the line beside it says how old the
/// list is, because it no longer re-reads itself on every open.
private struct ChannelTabBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ChannelTab.allCases) { option in
                let isOn = option == model.scraper.tab
                Button { model.showTab(option) } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Palette.onFill : Palette.ink(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(isOn ? Palette.accent : Palette.ink(0.08), in: ThemedCapsule())
                        .contentShape(ThemedCapsule())
                }
                .buttonStyle(.plain)
                .help("This channel's \(option.label.lowercased())")
                .pointingHand()
            }

            Spacer(minLength: 12)

            Group {
                if model.scraper.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Checking for new videos…")
                    }
                } else if let refreshed = model.scraper.refreshed {
                    // Re-drawn each minute so "just now" moves on.
                    TimelineView(.everyMinute) { _ in
                        Text(Self.updated(refreshed) + Self.added(model.scraper.added))
                    }
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Button {
                model.refreshListing()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
                    .chip()
            }
            .buttonStyle(.plain)
            .disabled(!model.scraper.canRefresh)
            .keyboardShortcut("r", modifiers: .command)
            .help("Look for new videos on this tab  (⌘R)")
            .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

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
            Divider()
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

    private var controls: some View {
        HStack(spacing: 10) {
            Text("Channels matching “\(model.search.query)”")
                .font(.system(size: 12.5, weight: .medium))
            Text(model.isLoadingList ? "Searching…" : "\(model.search.results.count)")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            if model.search.isBusy {
                ProgressView().controlSize(.small)
            }

            Text("Bookmark a channel to keep it in the side panel")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(height: 42)
    }
}


/// The one-line heading over each half of a channel's list.
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, accented ? 0 : 10)
    }
}


// MARK: - Toolbar control

/// One panel's button. Built on `Toggle` rather than `Button` so the chrome shows which
/// panels are open — the toolbar's pressed state is the only thing on screen saying so
/// once the tabs are gone, and the accent on the open one makes it unmissable.
private struct PanelToggle: View {
    let icon: String
    /// Carried for the tooltip and for VoiceOver. The button itself is the icon alone.
    let title: String
    var busy = false
    let isOn: Bool
    let help: String
    let toggle: () -> Void

    var body: some View {
        if Theme.active.id == .classic { system } else { themed }
    }

    /// A theme draws its own lit state. The toolbar's pressed fill is the system's and
    /// ignores the tint on a themed window, so an icon in `onFill` — near-black on the
    /// Nostromo — was being drawn on a dark pill and vanished.
    private var themed: some View {
        Button(action: toggle) {
            glyph
                .foregroundStyle(isOn ? Palette.onFill : Palette.ink(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(isOn ? Palette.accent : .clear,
                            in: ThemedRect(cornerRadius: 7, style: .continuous))
                .themeEdge(radius: 7, lit: isOn)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .pointingHand()
    }

    private var glyph: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 21, height: 16)
            .overlay(alignment: .topTrailing) {
                if busy {
                    Circle()
                        .fill(isOn ? Palette.onFill : Palette.accent)
                        .frame(width: 5.5, height: 5.5)
                }
            }
    }

    private var system: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in toggle() })) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                // White on the lit one, because the lit one is filled with the accent.
                .foregroundStyle(isOn ? AnyShapeStyle(Palette.onFill) : AnyShapeStyle(.primary))
                // The frame leaves the corner the dot sits in, so it is never clipped by
                // the button drawn around it.
                .frame(width: 21, height: 16)
                .overlay(alignment: .topTrailing) {
                    if busy {
                        Circle()
                            .fill(isOn ? Palette.onFill : Palette.accent)
                            .frame(width: 5.5, height: 5.5)
                    }
                }
        }
        .toggleStyle(.button)
        // Without this the pressed state is the user's system accent — blue, on a window
        // that has exactly one accent and it is red.
        .tint(Palette.accent)
        .help(help)
        .accessibilityLabel(title)
        .pointingHand()
    }
}
