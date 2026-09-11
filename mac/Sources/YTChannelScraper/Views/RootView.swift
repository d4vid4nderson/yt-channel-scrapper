import AppKit
import Combine
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Namespace private var hero

    /// The hero holds the whole window until there is something to show, then collapses
    /// to a header — the same move the web app made, and for the same reason: the search
    /// is the whole app until it isn't.
    private var collapsed: Bool { model.hasResults }

    /// One easing for the entire landing -> app transition, matching the web app's
    /// `cubic-bezier(.4, 0, .2, 1)` over .65s.
    private static let morph = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.65)

    /// The panels take room from the page rather than covering it, so whatever you were
    /// looking at is still there — and still usable — while you dig through what you have
    /// kept. Nothing is dimmed, because nothing is blocked.
    var body: some View {
        VStack(spacing: 0) {
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

                SavedVideosDrawer(model: model)
                    .drawerSlot(open: model.showVideosDrawer, side: .trailing)
            }

            VersionFooter(updater: model.appUpdater)
        }
        .frame(minWidth: 860, minHeight: 560)
        .animation(Layout.drawerEase, value: model.showChannelsDrawer)
        .animation(Layout.drawerEase, value: model.showVideosDrawer)
        .animation(Layout.drawerEase, value: model.showDownloads)
        .toolbar { chrome }
        // Dismissal goes through the model rather than straight at the flag, so closing
        // the sheet also clears whatever one-off answer it was showing.
        .sheet(isPresented: Binding(
            get: { model.appUpdater.isShowingResult },
            set: { if !$0 { model.appUpdater.dismissResult() } }
        )) {
            AppUpdateSheet(updater: model.appUpdater)
        }
        // Over everything, panels included: previewing something from a drawer has to
        // land on top of the panel it was started from.
        .overlay {
            PreviewModal(
                session: model.preview,
                download: { model.download([$0]) },
                popOut: { model.popOutToIsland() }
            )
        }
    }

    /// The app itself — hero, then results — in whatever width the panels have left it.
    private var page: some View {
        GeometryReader { geo in
            // One number drives the whole transition: the header's height. The results
            // are offset by exactly that, so they are revealed from underneath as it
            // shrinks rather than being covered by it — one motion, not two.
            let headerHeight = collapsed ? Layout.headerHeight : geo.size.height

            ZStack(alignment: .top) {
                resultsArea
                    .frame(
                        width: geo.size.width,
                        height: max(geo.size.height - Layout.headerHeight, 0)
                    )
                    .offset(y: headerHeight)

                header(height: headerHeight)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .animation(Self.morph, value: collapsed)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willMiniaturizeNotification)) { _ in
            // Minimising should not stop what you are watching.
            model.popOutToIsland()
        }
        .task {
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
        ToolbarItemGroup(placement: .primaryAction) {
            PanelToggle(
                icon: "rectangle.leadingthird.inset.filled",
                title: "Saved channels",
                isOn: model.showChannelsDrawer,
                help: "The channels you have saved  (⌘1)",
                toggle: model.toggleChannelsDrawer
            )
            PanelToggle(
                icon: "rectangle.bottomthird.inset.filled",
                title: "Downloads",
                // A dot, not a tally: that something is running is the part worth a mark
                // on the chrome, and the panel one click away has the numbers.
                busy: model.downloader.activeCount > 0,
                isOn: model.showDownloads,
                help: "What is downloading, and where it went  (⌘J)",
                toggle: model.toggleDownloads
            )
            PanelToggle(
                icon: "rectangle.trailingthird.inset.filled",
                title: "Saved videos",
                isOn: model.showVideosDrawer,
                help: "The videos you have saved  (⌘2)",
                toggle: model.toggleVideosDrawer
            )
        }
    }

    /// Always mounted, so its offset can animate. Off-screen below the hero until the
    /// header collapses and lifts it into view.
    private var resultsArea: some View {
        VStack(spacing: 0) {
            Divider()
            if let error = model.statusError, model.hasResults {
                ErrorBanner(message: error) { model.goHome() }
                Divider()
            }
            switch model.mode {
            // The saved list is a video list; everything about it is the same view.
            case .videos, .saved: ResultsList(model: model)
            case .channels:       ChannelResults(model: model)
            }
        }
    }

    // MARK: - Header

    private func header(height: CGFloat) -> some View {
        ZStack {
            Palette.ground
            if !collapsed {
                AuroraBackground().transition(.opacity)
            }

            if collapsed {
                HStack(spacing: 10) {
                    HomeButton(action: model.goHome)
                        .matchedGeometryEffect(id: "brand", in: hero)
                    SearchPill(model: model, compact: true)
                        .matchedGeometryEffect(id: "pill", in: hero)
                }
                .padding(.horizontal, Layout.gutter)
                .frame(maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 16) {
                        BrandMark(width: 62)
                            .matchedGeometryEffect(id: "brand", in: hero)
                        Text("YT Channel Scraper")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                            .fixedSize()
                            .transition(.opacity)
                    }
                    SearchPill(model: model, compact: false)
                        .matchedGeometryEffect(id: "pill", in: hero)
                        .frame(maxWidth: 680)
                        .padding(.top, 46)
                    statusLine
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
                    ProgressView().controlSize(.small).tint(.white)
                    Text(model.mode == .videos ? "Reading the channel…" : "Searching channels…")
                }
                .foregroundStyle(.white.opacity(0.75))
            } else if let error = model.statusError {
                Text(error)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.accent.opacity(0.9), in: RoundedRectangle(cornerRadius: 9))
            } else {
                Text("Paste a channel, or search for one by name.")
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .font(.system(size: 13))
        .padding(.top, 22)
        .frame(height: 48, alignment: .top)
        .transition(.opacity)
    }
}

// MARK: - Chrome

/// The brand mark, which doubles as the way back to the landing view.
private struct HomeButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            BrandMark(width: 30)
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .help("Back to the start — the URL is kept")
        .pointingHand()
        .accessibilityLabel("Back to the start")
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// The one rounded bar holding the URL field, the tab menu and Scrape. It is the same
/// view in both states — that is what lets it travel rather than cut.
private struct SearchPill: View {
    @Bindable var model: AppModel
    let compact: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            ZStack(alignment: .leading) {
                if model.urlText.isEmpty {
                    Text("Paste a channel URL or @handle — or type a name to search")
                        .foregroundStyle(.black.opacity(0.42))
                        .lineLimit(1)
                }
                TextField("", text: $model.urlText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.black)
                    .focused($focused)
                    .onSubmit { model.submit() }
            }
            .font(.system(size: compact ? 13 : 14))
            .padding(.leading, compact ? 14 : 18)

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
                    .foregroundStyle(.black)
                    + Text("  ")
                    + Text(Image(systemName: "chevron.down"))
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                    .foregroundStyle(.black.opacity(0.55))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 5 : 8)
            .background(.white, in: Capsule())
            .help("Which tab of the channel to list")
            .pointingHand()

            Button {
                model.isBusy ? model.stop() : model.submit()
            } label: {
                // The label is the answer to "what will return do with what I have
                // typed?", so it has to track the field rather than sit on one word.
                Text(buttonLabel)
                    .font(.system(size: compact ? 12.5 : 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 66 : 78)
                    .padding(.vertical, compact ? 7 : 10)
                    .background(
                        Palette.accent.opacity(model.canScrape || model.isBusy ? 1 : 0.45),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.canScrape && !model.isBusy)
            .keyboardShortcut(.return, modifiers: [])
            .help(helpText)
            .pointingHand()
        }
        .padding(compact ? 5 : 7)
        .background(Color(white: 0.89), in: Capsule())
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).lineLimit(2)
            Spacer(minLength: 8)
            Button("Start over", action: reset)
                .controlSize(.small)
                .help("Go back to the start, keeping the URL you typed")
                .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
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
            controls
            Divider()
            ScrollViewReader { proxy in
            ScrollView {
                // Cards, not list rows — they need the gap to read as separate surfaces.
                LazyVStack(spacing: 10) {
                    // Kept first, under a heading — a row that jumps the queue should
                    // say why it is there rather than leave you wondering whether the
                    // channel's order is broken.
                    if !model.keptVisible.isEmpty {
                        GroupLabel(text: "Kept from this channel", accented: true)
                        ForEach(model.keptVisible) { row($0) }
                        if !model.restVisible.isEmpty {
                            GroupLabel(text: "All videos")
                        }
                    }
                    ForEach(model.restVisible) { row($0) }

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
                        // Checked before the button, because the button unmounts the
                        // moment the scrape restarts — leaving the foot of the list
                        // blank for the whole fetch if nothing takes its place.
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(model.scraper.videos.isEmpty
                                 ? "Reading the channel…"
                                 : "Reading the next \(Scraper.pageSize)…")
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
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 22)
                .animation(.easeOut(duration: 0.24), value: model.keptVisible.count)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
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

    private func row(_ video: Video) -> some View {
        VideoRow(
            video: video,
            isPicked: model.picked.contains(video.id),
            isSaved: model.isSaved(video),
            inSavedList: model.mode == .saved,
            toggle: { model.toggle(video) },
            downloadOne: { model.download([video]) },
            preview: { model.preview.open(video) },
            toggleSaved: { model.toggleSaved(video) }
        )
        .id(video.id)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleAllVisible()
            } label: {
                HStack(spacing: 8) {
                    CheckBox(isOn: model.allVisiblePicked, size: 15)
                    Text("Select all").font(.system(size: 12.5))
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
                    .frame(width: 150)
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

            Spacer(minLength: 12)

            if model.scraper.isBusy {
                ProgressView().controlSize(.small)
            }

            // Quality and Download sit with the list they act on, the way the web app's
            // results bar had them, now that there is no window toolbar.
            Menu {
                Picker("Quality", selection: $model.quality) {
                    ForEach(Quality.menuOrder) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.quality.label).font(.system(size: 12.5))
                }
                .padding(.leading, 5)
                .padding(.trailing, 7)
                .padding(.vertical, 5)
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Which quality to fetch for the videos you pick")
            .pointingHand()

            Button {
                model.downloadPicked()
            } label: {
                Text(model.picked.isEmpty ? "Download" : "Download \(model.picked.count)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Palette.accent.opacity(model.picked.isEmpty ? 0.4 : 1),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.picked.isEmpty)
            .keyboardShortcut("d", modifiers: .command)
            .help(model.picked.isEmpty
                  ? "Tick some videos first, then download them here"
                  : "Download the \(model.picked.count) ticked video\(model.picked.count == 1 ? "" : "s") at \(model.quality.label)  (⌘D)")
            .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var countText: String {
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
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Text("Channels matching “\(model.search.query)”")
                .font(.system(size: 12.5, weight: .medium))
            Text("\(model.search.results.count)")
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
        Toggle(isOn: Binding(get: { isOn }, set: { _ in toggle() })) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                // White on the lit one, because the lit one is filled with the accent.
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                // The frame leaves the corner the dot sits in, so it is never clipped by
                // the button drawn around it.
                .frame(width: 21, height: 16)
                .overlay(alignment: .topTrailing) {
                    if busy {
                        Circle()
                            .fill(isOn ? .white : Palette.accent)
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
