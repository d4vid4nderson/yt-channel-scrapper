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
    @State private var model = AppModel()

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
        // Belt to `enterMinorMode()`'s braces. That method handles the ordinary route in,
        // but the mode also comes back off disk at launch — a minor's phone starts here
        // with `.search` never having been a valid selection.
        .onChange(of: model.isMinor) { _, isMinor in
            if isMinor && model.tab == .search { model.tab = .home }
        }
        .task {
            if model.isMinor && model.tab == .search { model.tab = .home }
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
                .background(Color.card, in: Capsule())
                .overlay(Capsule().stroke(Color.hairline))
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
        .background(Color.card, in: RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                .stroke(Color.hairline)
        }
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
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
