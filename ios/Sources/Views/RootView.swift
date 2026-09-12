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
        TabView {
            BrowseView(model: model)
                .tabItem { Label("Browse", systemImage: "magnifyingglass") }

            LibraryView(model: model)
                .tabItem { Label("Saved", systemImage: "star") }

            DownloadsView(model: model)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .badge(model.downloads.active)
        }
        .tint(Palette.accent)
        .sheet(item: $model.playing) { video in
            PlayerSheet(model: model, video: video)
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
