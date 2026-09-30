import AppIntents
import SwiftUI
import WidgetKit

/// Browsing channels and their videos from the Home Screen, without opening the app.
///
/// A widget cannot scroll, so browsing is paging: arrows step through the channels, a
/// channel opens onto its videos with a way back, and a video plays where it is — as
/// sound, through `PlayVideoIntent`, which runs in the app. Where the widget is looking
/// is kept in the App Group by the intents below, which run in the widget's own process;
/// what there is to look at is only ever what the app put in `WidgetSnapshot.shelves`.
struct BrowseWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Browse", intent: WidgetThemeIntent.self, provider: SnapshotProvider()) { entry in
            BrowseView(snapshot: entry.snapshot, state: BrowseState.load())
                .themedBackground(entry.snapshot)
        }
        .configurationDisplayName("Browse")
        .description("Page through your channels and play their videos, right from the Home Screen.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Where the widgets are looking

/// Kept in the App Group, written by the intents below and read when a widget draws.
struct BrowseState: Codable, Sendable {
    /// Browse: the channel open, or nil on the channel list.
    var channelID: String?
    /// Browse: the page within whichever list is showing.
    var page = 0
    /// Browse: the channel list's page, to go back to.
    var channelsPage = 0
    /// Now Playing's "More from": the page, and the channel it belongs to — a new channel
    /// starts again at the first page.
    var moreChannelID: String?
    var morePage = 0

    private static let key = "widget.browse.v1"

    private static var defaults: UserDefaults? {
        (Bundle.main.object(forInfoDictionaryKey: "YTCSAppGroup") as? String)
            .flatMap(UserDefaults.init(suiteName:))
    }

    static func load() -> BrowseState {
        guard let data = defaults?.data(forKey: key),
              let state = try? JSONDecoder().decode(BrowseState.self, from: data)
        else { return BrowseState() }
        return state
    }

    func save() {
        Self.defaults?.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    func morePage(for channelID: String) -> Int {
        moreChannelID == channelID ? morePage : 0
    }
}

struct BrowsePageIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Page"
    static let isDiscoverable = false

    @Parameter(title: "By") var delta: Int

    init() { delta = 1 }
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        var state = BrowseState.load()
        state.page = max(0, state.page + delta)
        state.save()
        return .result()
    }
}

struct MorePageIntent: AppIntent {
    static let title: LocalizedStringResource = "More From This Channel"
    static let isDiscoverable = false

    @Parameter(title: "By") var delta: Int
    @Parameter(title: "Channel") var channelID: String

    init() { delta = 1 }
    init(delta: Int, channelID: String) {
        self.delta = delta
        self.channelID = channelID
    }

    func perform() async throws -> some IntentResult {
        var state = BrowseState.load()
        state.morePage = max(0, state.morePage(for: channelID) + delta)
        state.moreChannelID = channelID
        state.save()
        return .result()
    }
}

struct BrowseOpenChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Channel"
    static let isDiscoverable = false

    @Parameter(title: "Channel") var channelID: String

    init() {}
    init(channelID: String) { self.channelID = channelID }

    func perform() async throws -> some IntentResult {
        var state = BrowseState.load()
        state.channelsPage = state.page
        state.channelID = channelID
        state.page = 0
        state.save()
        return .result()
    }
}

struct BrowseBackIntent: AppIntent {
    static let title: LocalizedStringResource = "Back to Channels"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var state = BrowseState.load()
        state.channelID = nil
        state.page = state.channelsPage
        state.save()
        return .result()
    }
}

// MARK: - Browse

struct BrowseView: View {
    let snapshot: WidgetSnapshot
    let state: BrowseState
    @Environment(\.widgetFamily) private var family

    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        // A channel that has since left the list falls back to the list, not a blank.
        if let id = state.channelID, let shelf = snapshot.shelves.first(where: { $0.id == id }) {
            channel(shelf)
        } else if snapshot.shelves.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(snapshot.look.accent.color)
                Spacer(minLength: 0)
                Text(snapshot.look.caps("Browse")).font(snapshot.look.display(size: 17))
                Text("Channels you keep will show up here").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(WidgetLink.open.url)
        } else {
            channels
        }
    }

    private var channels: some View {
        let (items, page, pages) = paged(snapshot.shelves, page: state.page, perPage: isLarge ? 8 : 4)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Caption("CHANNELS", snapshot)
                Spacer()
                Pager(page: page, pages: pages, look: snapshot.look, target: .browse)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                      spacing: 12) {
                ForEach(items) { shelf in
                    Button(intent: BrowseOpenChannelIntent(channelID: shelf.id)) {
                        VStack(spacing: 4) {
                            Avatar(item: shelf.channel, snapshot: snapshot)
                                .frame(maxWidth: 52)
                                .overlay(alignment: .bottomTrailing) {
                                    if shelf.id == snapshot.playingShelf?.id, snapshot.isPlaying {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(snapshot.look.onFill.color)
                                            .padding(4)
                                            .background(snapshot.look.accent.color, in: .circle)
                                    }
                                }
                            Text(shelf.channel.title)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            if isLarge { MiniPlayer(snapshot: snapshot) }
        }
    }

    private func channel(_ shelf: WidgetSnapshot.Shelf) -> some View {
        // Large holds four rows, or three with the mini player under them.
        let perPage = isLarge ? (snapshot.progress == nil ? 4 : 3) : 3
        let (items, page, pages) = paged(shelf.videos, page: state.page, perPage: perPage)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(intent: BrowseBackIntent()) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                        Avatar(item: shelf.channel, snapshot: snapshot).frame(width: 20)
                        Text(shelf.channel.title).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    .foregroundStyle(snapshot.look.accent.color)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                Pager(page: page, pages: pages, look: snapshot.look, target: .browse)
            }
            ShelfVideos(videos: items, perPage: perPage, rows: isLarge,
                        snapshot: snapshot, emptyNote: emptyNote)
            if isLarge { MiniPlayer(snapshot: snapshot) }
        }
    }

    private var emptyNote: String {
        snapshot.allowsSearch ? "Videos from this channel will show up after the app next opens."
                              : "Nothing from this channel yet."
    }
}

// MARK: - More from this channel

/// The foot of the large Now Playing widget: more from the channel that is playing.
struct MoreFromChannel: View {
    let shelf: WidgetSnapshot.Shelf
    let snapshot: WidgetSnapshot
    /// However many rows fit under what sits above it.
    var perPage = 3

    var body: some View {
        let state = BrowseState.load()
        let (items, page, pages) = paged(shelf.videos, page: state.morePage(for: shelf.id), perPage: perPage)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Caption("MORE FROM \(shelf.channel.title.uppercased())", snapshot)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Pager(page: page, pages: pages, look: snapshot.look, target: .more(shelf.id))
            }
            ShelfVideos(videos: items, perPage: perPage, rows: true, snapshot: snapshot,
                        emptyNote: snapshot.allowsSearch
                            ? "More from this channel will show up in a moment."
                            : "Nothing else from this channel yet.")
        }
    }
}

// MARK: - Pieces

/// One page of a list. The stored page only ever counts up — the dots step forward and
/// wrap — so it is taken round the number of pages, which also copes with a list that
/// got shorter since.
func paged<T>(_ all: [T], page: Int, perPage: Int) -> ([T], Int, Int) {
    let pages = max(1, Int((Double(all.count) / Double(perPage)).rounded(.up)))
    let page = max(page, 0) % pages
    let start = page * perPage
    return (Array(all[min(start, all.count)..<min(start + perPage, all.count)]), page, pages)
}

/// A page of videos, as tiles across or rows down.
private struct ShelfVideos: View {
    let videos: [WidgetSnapshot.ShelfVideo]
    let perPage: Int
    let rows: Bool
    let snapshot: WidgetSnapshot
    let emptyNote: String

    var body: some View {
        if videos.isEmpty {
            Spacer(minLength: 0)
            Text(emptyNote).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        } else if rows {
            ForEach(videos) { VideoButton(video: $0, snapshot: snapshot, style: .row) }
            Spacer(minLength: 0)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(videos) { VideoButton(video: $0, snapshot: snapshot, style: .tile) }
                // Keep a short last page's tiles the width of a full one's.
                ForEach(0..<(perPage - videos.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Page dots, the current one in the accent. Tapping them turns to the next page,
/// round to the first after the last — a widget cannot be swiped, so this is the
/// nearest thing, and one quiet control rather than a pair of arrows.
private struct Pager: View {
    enum Target { case browse, more(String) }

    let page: Int
    let pages: Int
    let look: WidgetSnapshot.Look
    let target: Target

    var body: some View {
        if pages > 1 {
            switch target {
            case .browse:
                Button(intent: BrowsePageIntent(delta: 1)) { dots }.buttonStyle(.plain)
            case .more(let channelID):
                Button(intent: MorePageIntent(delta: 1, channelID: channelID)) { dots }
                    .buttonStyle(.plain)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<min(pages, 8), id: \.self) { index in
                Capsule()
                    .fill(index == page ? look.accent.color : look.ink.color.opacity(0.28))
                    .frame(width: index == page ? 14 : 6, height: 6)
            }
        }
        // A bigger target than the dots themselves.
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .accessibilityLabel("Page \(page + 1) of \(pages). Next page")
    }
}

/// A video that plays when tapped, without opening the app. The one playing wears the
/// accent, so you can see where you are.
private struct VideoButton: View {
    enum Style { case tile, row }

    let video: WidgetSnapshot.ShelfVideo
    let snapshot: WidgetSnapshot
    let style: Style

    private var isCurrent: Bool { snapshot.isPlaying && snapshot.nowPlaying?.id == video.id }

    var body: some View {
        Button(intent: PlayVideoIntent(videoID: video.id, title: video.item.title,
                                       channelID: video.channelID, channelName: video.channelName)) {
            switch style {
            case .tile:
                VStack(alignment: .leading, spacing: 4) {
                    thumbnail
                    title.font(.system(size: 11, weight: .semibold)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .row:
                HStack(spacing: 10) {
                    thumbnail.frame(height: 44)
                    title.font(.caption.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: isCurrent ? "waveform" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(snapshot.look.accent.color)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var thumbnail: some View {
        Thumbnail(name: video.item.image, snapshot: snapshot)
            .overlay {
                if isCurrent {
                    ThemeShape(look: snapshot.look, radius: 8)
                        .stroke(snapshot.look.accent.color, lineWidth: 2)
                }
            }
    }

    private var title: some View {
        Text(video.item.title)
            .foregroundStyle(isCurrent ? snapshot.look.accent.color : snapshot.look.ink.color)
    }
}

/// A strip at the foot of the large Browse widget: what is playing, next, play/pause.
private struct MiniPlayer: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if let now = snapshot.nowPlaying, let progress = snapshot.progress {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(snapshot.look.accent.color)
                Text(now.title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button(intent: NextVideoIntent()) {
                    Image(systemName: "forward.end.fill").font(.system(size: 13))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                PlayPauseButton(progress: progress, look: snapshot.look, size: 28)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(snapshot.look.card.color, in: ThemeShape(look: snapshot.look, radius: 10))
        }
    }
}
