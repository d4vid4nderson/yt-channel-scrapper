import AVFoundation
import Combine
import SwiftUI

/// The three screens, as tabs.
///
/// The Mac app is one window with three drawers hanging off it, opened with ⌘1/⌘2/⌘3.
/// That is a keyboard's idea of navigation. A phone's is a tab bar, and the mapping is
/// almost one to one: Browse is the window, Saved is the two favourites drawers, and
/// Downloads is the downloads drawer — which gains a badge, because on a phone it is the
/// thing you leave and come back to.
struct RootView: View {
    @State private var model = AppModel.shared
    /// Up here with `model` so it survives the rebuild a theme change causes.
    @State private var pickingTheme = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            tabs
            // Sits on top of the tab bar's own strip rather than inside a tab, so it
            // survives switching tabs — which is the whole point of it.
            if model.playing == nil, let now = model.playback.current {
                NowPlayingBar(model: model, item: now.item, player: now.player)
                    .padding(.horizontal, 8)
                    .padding(.bottom, Self.tabBarHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: model.playback.item?.id)
        .animation(.easeOut(duration: 0.22), value: model.playing?.id)
        // Over everything on the page, tab bar included. The player is a sheet and so is
        // not under it: a video with scanlines drawn through it is not the point.
        .overlay { CRTGlass().ignoresSafeArea() }
        // Below `model`, which must survive a theme change: `themed()` rebuilds what it
        // wraps.
        .themed()
        // Belt to `enterMinorMode()`'s braces. That method handles the ordinary route in,
        // but the mode also comes back off disk at launch — a minor's phone starts here
        // with `.search` never having been a valid selection.
        .onChange(of: model.isMinor) { _, isMinor in
            if isMinor && (model.tab == .search || model.tab == .inbox) { model.tab = .home }
        }
        .task { await model.diagnoseIfAsked() }
        #if DEBUG
        // `-ytcsPlay <videoID>`: open the player on a video at launch, for exercising the
        // player and PiP in the simulator without tapping through. Debug builds only.
        .task {
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "-ytcsPlay"), index + 1 < args.count,
               let video = Video(json: ["id": args[index + 1], "title": "Debug"]) {
                model.play(video)
            }
        }
        #endif
        .task {
            model.applyChildSetup()
            if model.isMinor && (model.tab == .search || model.tab == .inbox) { model.tab = .home }
            await model.syncShelf()
        }
        // The shelf is a folder other devices write to, so the only honest time to read
        // it is when this one comes back to the front. A minor's device reconciles on the
        // same beat: coming back from the lock screen is when a withdrawn video should
        // stop being there.
        // A Mac delivering the family folder over the cable does not bring the app to the
        // front if it is already there, so a sync that only ran on foreground would sit
        // unread until the child next left and came back. Watched only while on screen.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            var seen = model.deliveredStamp
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                let now = model.deliveredStamp
                if now != seen {
                    seen = now
                    await model.syncShelf()
                }
            }
        }
        // The saved channels, refreshed every few hours while the app is open — each one
        // only once it is older than `ChannelCache.staleAfter`, so most checks ask
        // YouTube nothing. A minor's phone never reads a channel at all.
        .task(id: scenePhase) {
            guard scenePhase == .active, !model.isMinor else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30 * 60))
                guard !Task.isCancelled else { return }
                WidgetFeed.shared.update(from: model)
            }
        }
        // The widgets. Written on the way out as well as in, so they show the phone as it
        // was left — and whenever what they show changes while the app is open.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { WidgetFeed.shared.update(from: model) }
        }
        .onChange(of: model.playback.item?.id) { WidgetFeed.shared.update(from: model) }
        .onChange(of: ThemeStore.shared.selection) { WidgetFeed.shared.update(from: model) }
        .onChange(of: RepeatSetting.shared.mode) { WidgetFeed.shared.update(from: model) }
        .onChange(of: model.library.channels.count) { WidgetFeed.shared.update(from: model) }
        .onOpenURL { url in
            guard let link = WidgetLink(url: url) else { return }
            open(link)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // The icon is matched to the theme on every return to the front, not only
            // when the theme is picked: a phone that was already on a theme when an
            // update brought the icons would otherwise never get its own. A no-op when
            // they already match, so iOS only says "icon changed" when it has.
            ThemeChrome.applyIcon(ThemeStore.shared.theme)
            model.applyChildSetup()
            Task {
                await model.syncShelf()
                WidgetFeed.shared.update(from: model)
            }
        }
    }

    /// Where a widget's tap lands.
    ///
    /// Nothing here grants anything the app would not: a video goes through
    /// `AppModel.play`, which refuses on a minor's phone what is not approved, and search
    /// is not offered there at all — the scheme is open to any app on the phone, not only
    /// the widget.
    private func open(_ link: WidgetLink) {
        switch link {
        case .open:
            break
        case .resume:
            if let item = model.playback.item { model.playing = item }
        case .airplay:
            // Once the app is on screen: the picker needs a window to present from.
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                RoutePicker.present()
            }
        case .video(let id, let title, let channelID, let channelName):
            var json: [String: Any] = ["id": id, "title": title]
            if let channelID { json["channel_id"] = channelID }
            if let channelName { json["channel"] = channelName }
            let known = model.savedVideos.first { $0.id == id }
            if let video = known ?? Video(json: json) { model.play(video) }
        case .channel(let id):
            guard let channel = model.library.channels.first(where: { $0.id == id }) else { return }
            model.playing = nil
            model.tab = .home
            model.homePath = [channel]
        case .search:
            guard !model.isMinor else { return }
            model.playing = nil
            model.tab = .search
            // A beat for the tab to be on screen: a search field that is not in the
            // window yet cannot take the keyboard.
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                model.searchActive = true
            }
        }
    }

    /// The compact tab bar's height, which is fixed on iPhone. The bar is laid out in the
    /// window's safe area — above the home indicator, but still over the tabs — so it is
    /// lifted by exactly the strip it must not cover.
    private static let tabBarHeight: CGFloat = 49

    private var tabs: some View {
        TabView(selection: $model.tab) {
            HomeView(model: model)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppModel.Tab.home)

            // The one tab Minor Mode is really about. Hidden rather than disabled: a
            // greyed-out Search tab is an invitation to keep tapping it, and there is
            // nothing to say to someone who does.
            if !model.isMinor {
                SearchView(model: model)
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(AppModel.Tab.search)
            }

            // What other admins have sent this device, to keep or ignore. Not on a minor's
            // phone: there, what a parent sends goes straight onto Home — it has already
            // been decided, and asking the child to accept it again was a step with
            // nothing behind it.
            if !model.isMinor {
                InboxView(model: model)
                    .tabItem { Label("Inbox", systemImage: "tray") }
                    .badge(model.unreadCount)
                    .tag(AppModel.Tab.inbox)
            }

            DownloadsView(model: model)
                .tabItem {
                    Label(model.isMinor ? "Downloaded" : "Downloads",
                          systemImage: "arrow.down.circle")
                }
                .badge(model.isMinor ? 0 : model.downloads.active)
                .tag(AppModel.Tab.downloads)
        }
        .tint(Palette.accent)
        .sheet(item: $model.playing) { item in
            PlayerSheet(model: model, item: item)
        }
        .sheet(isPresented: $pickingTheme) {
            // Closed in the same breath as the switch, so the tree the new theme rebuilds
            // does not find the sheet still asked for and bring it straight back.
            ThemeGallery { id in
                pickingTheme = false
                ThemeStore.shared.selection = id
            }
        }
        // The Home Screen's Change Theme quick action. `initial` catches the one that
        // launched the app cold, which lands before this view exists.
        .onChange(of: QuickActions.shared.pending, initial: true) { _, action in
            guard action == .changeTheme else { return }
            QuickActions.shared.pending = nil
            // One sheet at a time: a video that is open steps down to the Now Playing
            // bar and keeps playing.
            if model.playing != nil {
                model.playing = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    pickingTheme = true
                }
            } else {
                pickingTheme = true
            }
        }
        .overlay(alignment: .top) { banner }
        .animation(.easeInOut(duration: 0.2), value: model.banner)
    }

    /// A short-lived message for the things with no row of their own to report into — an
    /// import result, a queued batch.
    @ViewBuilder
    private var banner: some View {
        if let message = model.banner {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.primaryText)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.card, in: ThemedCapsule())
                .overlay(ThemedCapsule().stroke(Color.hairline))
                .themeEdge(ThemedCapsule())
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                .padding(.horizontal, Metrics.gutter)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { model.banner = nil }
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(4))
                    if model.banner == message { model.banner = nil }
                }
        }
    }
}

/// What is still playing, after the player's screen has gone.
///
/// The phone has no notch island to hand a video up to, so this is the equivalent: a
/// strip above the tab bar that says what is going, lets you stop it, and takes you back
/// to the full player when you tap it. Without it, "closing the sheet keeps playing"
/// would be a video with no visible off switch, which is worse than stopping it.
private struct NowPlayingBar: View {
    @Bindable var model: AppModel
    let item: Playable
    let player: AVPlayer

    /// Mirrors the player rather than the button that was last pressed: the lock screen,
    /// the headphones and an interruption can all change it from outside this view.
    @State private var isPlaying = true

    var body: some View {
        HStack(spacing: 10) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Button {
                isPlaying ? player.pause() : player.play()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.primaryText)
                    .tappable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            AirPlayButton()
                .frame(width: 36, height: 36)
                .accessibilityLabel("AirPlay")

            Button {
                model.stopPlaying()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .tappable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .card()
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        // The row itself is the way back into the player; the two buttons keep their own
        // taps, so the target for reopening is everything that is not one of them.
        .contentShape(Rectangle())
        .onTapGesture { model.playing = item }
        .accessibilityElement(children: .contain)
        .onReceive(player.publisher(for: \.timeControlStatus)) {
            isPlaying = $0 != .paused
        }
    }

    private var artwork: some View {
        AsyncImage(url: item.artwork) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Color.black
            }
        }
        .frame(width: 52, height: 30)
        .clipShape(ThemedRect(cornerRadius: 6, style: .continuous))
    }
}
