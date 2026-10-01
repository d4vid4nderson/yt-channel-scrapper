import AppIntents
import SwiftUI
import WidgetKit

/// The Home and Lock Screen widgets.
///
/// Five, each one thing, so the gallery offers a choice rather than one widget trying to
/// be everything at every size: what is playing, recent videos, channels, all of it at
/// once, and a search button. Every one of them draws `WidgetSnapshot` and nothing else —
/// what goes in it, and what a minor's phone may show, is decided by the app
/// (`WidgetFeed`).
@main
struct YTPlayerWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        RecentVideosWidget()
        ChannelsWidget()
        DashboardWidget()
        BrowseWidget()
        SearchWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// One entry, never refreshed on a schedule: the app reloads the widgets whenever
/// something they show changes, and there is nothing to show that it did not write.
struct SnapshotProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func snapshot(for configuration: WidgetThemeIntent, in context: Context) async -> SnapshotEntry {
        var snapshot = WidgetSnapshot.load()
        // The gallery preview, before the app has ever written anything.
        let hasContent = snapshot.nowPlaying != nil || !snapshot.videos.isEmpty
            || !snapshot.channels.isEmpty
        if context.isPreview && !hasContent { snapshot = .sample }
        return SnapshotEntry(date: .now, snapshot: configuration.apply(to: snapshot))
    }

    func timeline(for configuration: WidgetThemeIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let entry = SnapshotEntry(date: .now,
                                  snapshot: configuration.apply(to: WidgetSnapshot.load()))
        return Timeline(entries: [entry], policy: .never)
    }
}

/// Edit Widget's one option: which theme this widget wears. Same as App follows the
/// app's theme and is the default; anything else pins this widget to that theme, so a
/// Home Screen can mix them.
struct WidgetThemeIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Theme"
    static let description = IntentDescription("Choose how this widget looks.")

    @Parameter(title: "Theme", default: .sameAsApp)
    var theme: WidgetTheme

    func apply(to snapshot: WidgetSnapshot) -> WidgetSnapshot {
        guard theme != .sameAsApp,
              let chosen = snapshot.themes.first(where: { $0.id == theme.rawValue })
        else { return snapshot }
        var snapshot = snapshot
        snapshot.look = chosen.look
        return snapshot
    }
}

/// The themes, as a fixed list the Edit Widget menu can draw at once.
///
/// Fixed rather than read from what the app wrote because a list that has to be fetched
/// makes the menu open, load, then re-lay itself out — visibly jumping on screen. The
/// cost is keeping this in step with `Theme.ID`: a theme added there needs a case here
/// (raw value = its id) to be pickable, and until then a widget can still follow it
/// through Same as App. The colours still come from the app, by id.
enum WidgetTheme: String, AppEnum {
    case sameAsApp
    case classic, bladeRunner, dune, middleEarth, synthwave, grid, ringWorld, cyberMead

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Theme"
    static let caseDisplayRepresentations: [WidgetTheme: DisplayRepresentation] = [
        .sameAsApp: "Same as App",
        .classic: "Classic",
        .bladeRunner: "Blade Runner 2049",
        .dune: "Dune",
        .middleEarth: "Middle-earth",
        .synthwave: "Glitch",
        .grid: "The Grid",
        .ringWorld: "Ring World",
        .cyberMead: "Cyber Mead",
    ]
}

extension WidgetSnapshot {
    /// What the gallery shows before the app has written a real snapshot.
    static var sample: WidgetSnapshot {
        func item(_ n: Int, _ title: String, _ subtitle: String) -> Item {
            Item(id: "\(n)", title: title, subtitle: subtitle, image: nil, link: WidgetLink.open.url)
        }
        var s = WidgetSnapshot.empty
        s.nowPlaying = item(0, "Something good to watch", "A favourite channel")
        s.isPlaying = true
        s.videos = (1...6).map { item($0, "Video \($0)", "Channel") }
        s.channels = ["Science", "Music", "Lego", "Space", "Art", "Nature", "Games", "Cars"]
            .enumerated().map { item($0.offset + 10, $0.element, "") }
        s.allowsSearch = true
        return s
    }
}

// MARK: - The widgets

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NowPlaying", intent: WidgetThemeIntent.self, provider: SnapshotProvider()) { entry in
            NowPlayingView(snapshot: entry.snapshot).themedBackground(entry.snapshot)
        }
        .configurationDisplayName("Now Playing")
        .description("What's playing, with controls — and at large size, more from the same channel.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular])
    }
}

struct RecentVideosWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RecentVideos", intent: WidgetThemeIntent.self, provider: SnapshotProvider()) { entry in
            RecentVideosView(snapshot: entry.snapshot).themedBackground(entry.snapshot)
        }
        .configurationDisplayName("Recent Videos")
        .description("Videos you watched recently. Tap one to play it.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ChannelsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Channels", intent: WidgetThemeIntent.self, provider: SnapshotProvider()) { entry in
            ChannelsView(snapshot: entry.snapshot).themedBackground(entry.snapshot)
        }
        .configurationDisplayName("Channels")
        .description("Your channels, most recently opened first.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DashboardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Dashboard", intent: WidgetThemeIntent.self, provider: SnapshotProvider()) { entry in
            DashboardView(snapshot: entry.snapshot).themedBackground(entry.snapshot)
        }
        .configurationDisplayName("YT Player")
        .description("What's playing, recent videos and channels, and search, all in one.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SearchWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Search", intent: WidgetThemeIntent.self, provider: SnapshotProvider()) { entry in
            SearchView(snapshot: entry.snapshot).themedBackground(entry.snapshot)
        }
        .configurationDisplayName("Search")
        .description("Jump straight into searching for videos and channels.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Now Playing

struct NowPlayingView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var label: String {
        guard snapshot.isPlaying else { return "LAST WATCHED" }
        return snapshot.progress?.isPaused == true ? "PAUSED" : "NOW PLAYING"
    }

    var body: some View {
        if let item = snapshot.nowPlaying {
            content(item).widgetURL(item.link)
        } else {
            empty.widgetURL(WidgetLink.open.url)
        }
    }

    @ViewBuilder
    private func content(_ item: WidgetSnapshot.Item) -> some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: snapshot.isPlaying ? "play.fill" : "arrow.counterclockwise")
                    .font(.title2)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(label.capitalized, systemImage: "play.rectangle.fill")
                    .font(.caption2.weight(.semibold))
                Text(item.title).font(.headline).lineLimit(snapshot.progress == nil ? 2 : 1)
                if let progress = snapshot.progress {
                    LiveBar(progress: progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemLarge where snapshot.progress != nil:
            // Top to bottom: the video, its controls, then more from its channel. Sized
            // to fit with room to spare — a large widget whose content runs taller than it
            // is gets pushed up into its own top margin rather than clipped.
            PlayerLarge(item: item, snapshot: snapshot)
        case .systemLarge:
            VStack(alignment: .leading, spacing: 12) {
                content(forMedium: item).frame(height: 124)
                Caption("RECENT VIDEOS", snapshot)
                ForEach(snapshot.videos.filter { $0.id != item.id }.prefix(3)) {
                    VideoRow(item: $0, snapshot: snapshot)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        case .systemMedium where snapshot.progress != nil:
            PlayerMedium(item: item, snapshot: snapshot)
        case .systemSmall where snapshot.progress != nil:
            PlayerSmall(item: item, snapshot: snapshot)
        case .systemMedium:
            content(forMedium: item)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Thumbnail(name: item.image, snapshot: snapshot)
                Caption(label, snapshot)
                Text(item.title).font(.caption.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
            }
        }
    }

    /// The medium layout when nothing is in the player: the last thing watched, to
    /// play again.
    private func content(forMedium item: WidgetSnapshot.Item) -> some View {
        HStack(spacing: 12) {
            Thumbnail(name: item.image, snapshot: snapshot)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                Caption(label, snapshot)
                Text(item.title).font(.headline).lineLimit(3)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Label(snapshot.isPlaying ? "Resume" : "Play again", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.look.accent.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "play.rectangle.fill").font(.title2)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(snapshot.look.caps("YT Player")).font(snapshot.look.display(size: 17))
                Text("Nothing playing").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            OpenApp(snapshot: snapshot, detail: "Nothing playing yet")
        }
    }
}

// MARK: - Recent videos

struct RecentVideosView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let videos = snapshot.videos
        if videos.isEmpty {
            OpenApp(snapshot: snapshot, detail: "Videos you watch will show up here")
                .widgetURL(WidgetLink.open.url)
        } else {
            switch family {
            case .systemSmall:
                // A small widget has one tap target, so it is one video.
                VStack(alignment: .leading, spacing: 6) {
                    Caption("RECENT", snapshot)
                    Thumbnail(name: videos[0].image, snapshot: snapshot)
                    Text(videos[0].title).font(.caption.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                }
                .widgetURL(videos[0].link)
            case .systemMedium:
                VStack(alignment: .leading, spacing: 8) {
                    Caption("RECENT VIDEOS", snapshot)
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(videos.prefix(3)) { VideoTile(item: $0, snapshot: snapshot) }
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Caption("RECENT VIDEOS", snapshot)
                    ForEach(videos.prefix(5)) { VideoRow(item: $0, snapshot: snapshot) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Channels

struct ChannelsView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let channels = snapshot.channels
        if channels.isEmpty {
            OpenApp(snapshot: snapshot, detail: "Channels you keep will show up here")
                .widgetURL(WidgetLink.open.url)
        } else {
            switch family {
            case .systemSmall:
                // One tap target: the four avatars are a picture of the shelf, and the tap
                // opens the one on top.
                VStack(alignment: .leading, spacing: 8) {
                    Caption("CHANNELS", snapshot)
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        ForEach(Array(stride(from: 0, to: min(channels.count, 4), by: 2)), id: \.self) { row in
                            GridRow {
                                ForEach(channels[row..<min(row + 2, channels.count)]) {
                                    Avatar(item: $0, snapshot: snapshot)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .widgetURL(channels[0].link)
            case .systemMedium:
                VStack(alignment: .leading, spacing: 8) {
                    Caption("CHANNELS", snapshot)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(channels.prefix(4)) { ChannelTile(item: $0, snapshot: snapshot) }
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 10) {
                    Caption("CHANNELS", snapshot)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                              spacing: 14) {
                        ForEach(channels.prefix(8)) { ChannelTile(item: $0, snapshot: snapshot) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Everything

struct DashboardView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Link(destination: WidgetLink.open.url) {
                    Text(snapshot.look.caps("YT Player")).font(snapshot.look.display(size: 17))
                }
                Spacer()
                if snapshot.allowsSearch { SearchPill(snapshot: snapshot) }
            }

            if let now = snapshot.nowPlaying {
                Link(destination: now.link) {
                    HStack(spacing: 10) {
                        Thumbnail(name: now.image, snapshot: snapshot)
                            .frame(height: family == .systemLarge ? 64 : 50)
                        VStack(alignment: .leading, spacing: 3) {
                            Caption(snapshot.isPlaying ? "NOW PLAYING" : "LAST WATCHED", snapshot)
                            Text(now.title).font(.caption.weight(.semibold)).lineLimit(2)
                            if let progress = snapshot.progress {
                                Waveform(seed: now.id, progress: progress, look: snapshot.look)
                                    .frame(height: 14)
                            }
                        }
                        Spacer(minLength: 0)
                        if let progress = snapshot.progress {
                            PlayPauseButton(progress: progress, look: snapshot.look, size: 34)
                        }
                    }
                }
            }

            if family == .systemLarge {
                if !snapshot.videos.isEmpty {
                    Caption("RECENT VIDEOS", snapshot)
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(snapshot.videos.prefix(3)) { VideoTile(item: $0, snapshot: snapshot) }
                    }
                }
                if !snapshot.channels.isEmpty {
                    Caption("CHANNELS", snapshot)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(snapshot.channels.prefix(4)) { ChannelTile(item: $0, snapshot: snapshot) }
                    }
                }
            } else if snapshot.nowPlaying == nil {
                // Medium with nothing played yet: the channels fill the space instead.
                HStack(alignment: .top, spacing: 8) {
                    ForEach(snapshot.channels.prefix(4)) { ChannelTile(item: $0, snapshot: snapshot) }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Search

struct SearchView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        // A minor's phone has no Search tab. The widget still works — it opens the app —
        // rather than sitting there as a button that does nothing.
        let link = snapshot.allowsSearch ? WidgetLink.search.url : WidgetLink.open.url
        let icon = snapshot.allowsSearch ? "magnifyingglass" : "play.rectangle.fill"
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: icon).font(.title2)
                }
            case .accessoryRectangular:
                HStack {
                    Image(systemName: icon).font(.title3)
                    Text(snapshot.allowsSearch ? "Search YouTube" : "Open YT Player")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(snapshot.look.accent.color)
                    Spacer(minLength: 0)
                    Text(snapshot.look.caps(snapshot.allowsSearch ? "Search" : "YT Player"))
                        .font(snapshot.look.display(size: 17))
                    Text(snapshot.allowsSearch ? "Videos and channels" : "Open your videos")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(link)
    }
}

// MARK: - Player

/// Now Playing at medium size while something is in the player: the picture on one
/// side; the channel, title, waveform and transport on the other.
struct PlayerMedium: View {
    let item: WidgetSnapshot.Item
    let snapshot: WidgetSnapshot

    var body: some View {
        let progress = snapshot.progress!
        HStack(alignment: .top, spacing: 12) {
            // The art takes the whole height of the widget, cropped to fill it — album art,
            // not a thumbnail in a column.
            Color.clear
                .overlay {
                    if let image = load(item.image) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ZStack {
                            snapshot.look.card.color
                            Image(systemName: "play.rectangle.fill")
                                .font(.title)
                                .foregroundStyle(snapshot.look.accent.color)
                        }
                    }
                }
                .frame(width: 140)
                .frame(maxHeight: .infinity)
                .clipShape(ThemeShape(look: snapshot.look, radius: 12))

            VStack(alignment: .leading, spacing: 4) {
                // The channel, where a label would say "now playing" — the controls
                // already say that.
                if let channel = item.subtitle {
                    Caption(channel, snapshot).lineLimit(1)
                }
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
                // Elapsed | waveform | remaining, on one line: the times belong to the
                // thing that is moving.
                HStack(spacing: 5) {
                    Times.Elapsed(progress: progress)
                    Waveform(seed: item.id, progress: progress, look: snapshot.look)
                        .frame(height: 20)
                    Times.Remaining(progress: progress)
                }
                Transport(snapshot: snapshot, progress: progress)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Large, while something plays: the video as a banner with its title on it — a widget
/// shows pictures, never moving ones, so this is the poster rather than the video — then
/// the waveform and transport, then more from the channel.
struct PlayerLarge: View {
    let item: WidgetSnapshot.Item
    let snapshot: WidgetSnapshot

    var body: some View {
        let progress = snapshot.progress!
        VStack(alignment: .leading, spacing: 8) {
            // The art takes whatever height the rest leaves, so the widget is filled on
            // every phone size instead of ending in a gap.
            Color.clear
                .frame(minHeight: 100, maxHeight: .infinity)
                .overlay {
                    if let image = load(item.image) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        snapshot.look.card.color
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        if let channel = item.subtitle {
                            Text(channel)
                                .font(snapshot.look.display(size: 10))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                               startPoint: .top, endPoint: .bottom))
                }
                .clipShape(ThemeShape(look: snapshot.look, radius: 12))

            HStack(spacing: 6) {
                Times.Elapsed(progress: progress)
                Waveform(seed: item.id, progress: progress, look: snapshot.look)
                    .frame(height: 18)
                Times.Remaining(progress: progress)
            }
            Transport(snapshot: snapshot, progress: progress)

            if let shelf = snapshot.playingShelf {
                MoreFromChannel(shelf: shelf, snapshot: snapshot, perPage: 2)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Small: the picture with play/pause on it — the one button that fits — and the
/// waveform under the title.
struct PlayerSmall: View {
    let item: WidgetSnapshot.Item
    let snapshot: WidgetSnapshot

    var body: some View {
        let progress = snapshot.progress!
        VStack(alignment: .leading, spacing: 6) {
            Thumbnail(name: item.image, snapshot: snapshot)
                .overlay(alignment: .bottomTrailing) {
                    PlayPauseButton(progress: progress, look: snapshot.look, size: 30)
                        .padding(4)
                }
            Text(item.title).font(.caption.weight(.semibold)).lineLimit(2)
            Spacer(minLength: 0)
            Waveform(seed: item.id, progress: progress, look: snapshot.look)
                .frame(height: 16)
        }
    }
}

/// Repeat, back, play/pause, forward, AirPlay.
struct Transport: View {
    let snapshot: WidgetSnapshot
    let progress: WidgetSnapshot.Progress

    var body: some View {
        let look = snapshot.look
        HStack(spacing: 0) {
            Button(intent: CycleRepeatIntent()) {
                Image(systemName: snapshot.repeatMode.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(snapshot.repeatMode == .off
                                     ? look.ink.color.opacity(0.45) : look.accent.color)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            Button(intent: SkipPlaybackIntent(seconds: -15)) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            PlayPauseButton(progress: progress, look: look, size: 32)
                .frame(maxWidth: .infinity)
            Button(intent: SkipPlaybackIntent(seconds: 15)) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            // A widget cannot show the AirPlay list itself; this opens the app with it up.
            Link(destination: WidgetLink.airplay.url) {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
        }
        .buttonStyle(.plain)
    }
}

struct PlayPauseButton: View {
    let progress: WidgetSnapshot.Progress
    let look: WidgetSnapshot.Look
    let size: CGFloat

    var body: some View {
        Button(intent: TogglePlaybackIntent()) {
            Image(systemName: progress.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(look.onFill.color)
                .frame(width: size, height: size)
                .background(look.accent.color, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(progress.isPaused ? "Play" : "Pause")
    }
}

/// Bars in the shape of a waveform, filling with the accent as the video plays.
///
/// Not the video's real sound — the widget has no audio to look at — but a shape of its
/// own for each video, so two videos do not wear the same one. The fill is a live
/// `ProgressView(timerInterval:)` squashed into the bars: WidgetKit keeps that moving by
/// itself, which is the only way a widget shows something advancing without being
/// rewritten every second.
struct Waveform: View {
    let seed: String
    let progress: WidgetSnapshot.Progress
    let look: WidgetSnapshot.Look

    var body: some View {
        let bars = WaveBars(seed: seed)
        ZStack {
            bars.fill(look.ink.color.opacity(0.22))
            fill
                .mask(bars)
        }
    }

    @ViewBuilder
    private var fill: some View {
        if let interval = progress.interval {
            ProgressView(timerInterval: interval, countsDown: false,
                         label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.linear)
                .tint(look.accent.color)
                .scaleEffect(x: 1, y: 12, anchor: .center)
        } else {
            GeometryReader { geometry in
                look.accent.color
                    .frame(width: geometry.size.width * progress.fraction)
            }
        }
    }
}

struct WaveBars: Shape {
    let seed: String

    func path(in rect: CGRect) -> Path {
        let count = max(Int(rect.width / 4.5), 8)
        let gap: CGFloat = 1.5
        let width = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
        // A small generator seeded from the video id, so the shape is the same every
        // time that video is drawn.
        var state = seed.unicodeScalars.reduce(UInt64(1469598103934665603)) {
            ($0 ^ UInt64($1.value)) &* 1099511628211
        }
        var path = Path()
        for index in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let noise = Double(state >> 33) / Double(UInt32.max)
            // A gentle swell under the noise, so it reads as music rather than static.
            let swell = 0.55 + 0.45 * sin(Double(index) / Double(count) * .pi * 3)
            let height = max(rect.height * CGFloat(0.2 + 0.8 * noise * swell), 2)
            let x = rect.minX + CGFloat(index) * (width + gap)
            path.addRoundedRect(in: CGRect(x: x, y: rect.midY - height / 2,
                                           width: width, height: height),
                                cornerSize: CGSize(width: width / 2, height: width / 2))
        }
        return path
    }
}

/// Elapsed and remaining, counting live while it plays.
enum Times {
    struct Elapsed: View {
        let progress: WidgetSnapshot.Progress

        var body: some View {
            Group {
                if let interval = progress.interval {
                    Text(timerInterval: interval, countsDown: false)
                } else {
                    Text(clock(progress.elapsed))
                }
            }
            .modifier(TimeStyle(progress: progress))
        }
    }

    struct Remaining: View {
        let progress: WidgetSnapshot.Progress

        var body: some View {
            Group {
                if let interval = progress.interval {
                    Text(timerInterval: interval, countsDown: true)
                } else if let duration = progress.duration {
                    Text(clock(duration - progress.elapsed))
                }
            }
            .modifier(TimeStyle(progress: progress))
        }
    }

    /// A live timer text is as wide as the longest time it could show, so both sides are
    /// pinned to one width — the same on each, so the two read as a pair — that fits
    /// h:mm:ss when the video runs an hour or more and m:ss otherwise.
    private struct TimeStyle: ViewModifier {
        let progress: WidgetSnapshot.Progress

        func body(content: Content) -> some View {
            let long = (progress.duration ?? 0) >= 3600
            content
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: long ? 52 : 34)
        }
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// A plain progress line for the Lock Screen, where the system tints everything.
struct LiveBar: View {
    let progress: WidgetSnapshot.Progress

    var body: some View {
        if let interval = progress.interval {
            ProgressView(timerInterval: interval, countsDown: false,
                         label: { EmptyView() }, currentValueLabel: { EmptyView() })
        } else {
            ProgressView(value: progress.fraction)
        }
    }
}

// MARK: - Pieces

struct Caption: View {
    let text: String
    let snapshot: WidgetSnapshot
    init(_ text: String, _ snapshot: WidgetSnapshot) { self.text = text; self.snapshot = snapshot }

    var body: some View {
        Text(text)
            .font(snapshot.look.display(size: 10))
            .kerning(0.6)
            .foregroundStyle(snapshot.look.accent.color)
    }
}

/// A video's 16:9 picture, or a tinted stand-in when there is none on disk.
struct Thumbnail: View {
    let name: String?
    let snapshot: WidgetSnapshot

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image = load(name) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        snapshot.look.card.color
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(snapshot.look.accent.color)
                    }
                }
            }
            .clipShape(ThemeShape(look: snapshot.look, radius: 8))
    }
}

struct Avatar: View {
    let item: WidgetSnapshot.Item
    let snapshot: WidgetSnapshot

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = load(item.image) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        snapshot.look.card.color
                        Text(monogram(item.title))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(snapshot.look.ink.color)
                    }
                }
            }
            .clipShape(.circle)
    }
}

struct VideoTile: View {
    let item: WidgetSnapshot.Item
    let snapshot: WidgetSnapshot

    var body: some View {
        Link(destination: item.link) {
            VStack(alignment: .leading, spacing: 4) {
                Thumbnail(name: item.image, snapshot: snapshot)
                Text(item.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct VideoRow: View {
    let item: WidgetSnapshot.Item
    let snapshot: WidgetSnapshot

    var body: some View {
        Link(destination: item.link) {
            HStack(spacing: 10) {
                Thumbnail(name: item.image, snapshot: snapshot).frame(height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.caption.weight(.semibold)).lineLimit(2)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct ChannelTile: View {
    let item: WidgetSnapshot.Item
    let snapshot: WidgetSnapshot

    var body: some View {
        Link(destination: item.link) {
            VStack(spacing: 4) {
                Avatar(item: item, snapshot: snapshot).frame(maxWidth: 52)
                Text(item.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct SearchPill: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Link(destination: WidgetLink.search.url) {
            Label("Search", systemImage: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(snapshot.look.accent.color, in: ThemeShape(look: snapshot.look, radius: 12))
                .foregroundStyle(snapshot.look.onFill.color)
        }
    }
}

/// What a widget with nothing to show yet says: the app's name, and a tap opens it.
struct OpenApp: View {
    let snapshot: WidgetSnapshot
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(snapshot.look.accent.color)
            Spacer(minLength: 0)
            Text(snapshot.look.caps("YT Player")).font(snapshot.look.display(size: 17))
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

func load(_ name: String?) -> UIImage? {
    guard let name, let url = WidgetSnapshot.imageURL(name) else { return nil }
    return UIImage(contentsOfFile: url.path)
}

func monogram(_ title: String) -> String {
    title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
}

extension WidgetSnapshot.RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

extension WidgetSnapshot.Look {
    var fontDesign: Font.Design {
        switch design {
        case "serif": .serif
        case "rounded": .rounded
        case "monospaced": .monospaced
        default: .default
        }
    }

    var fontWidth: Font.Width {
        switch width {
        case "condensed": .condensed
        case "compressed": .compressed
        case "expanded": .expanded
        default: .standard
        }
    }

    /// A heading in the theme's display face, where this phone has it.
    func display(size: CGFloat) -> Font {
        if let displayFont, UIFont(name: displayFont, size: size) != nil {
            return .custom(displayFont, fixedSize: size)
        }
        return .system(size: size, weight: .bold, design: fontDesign)
    }

    func caps(_ text: String) -> String { displayCaps ? text.uppercased() : text }
}

/// A container's outline, cut the way the theme cuts corners — the widget's copy of
/// `ThemedRect`, which lives in the app.
struct ThemeShape: Shape {
    let look: WidgetSnapshot.Look
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius * look.cornerScale, min(rect.width, rect.height) / 2)
        switch look.corners {
        case "square":
            return Path(rect)
        case "chamfered":
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.closeSubpath()
            return path
        default:
            return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        }
    }
}

extension View {
    /// The theme on a widget: its ground, lit from one corner by its accent the way the
    /// app's backdrop is — still, since a widget does not animate — and its type.
    /// On the Lock Screen the system tints everything itself and ignores all of this.
    func themedBackground(_ snapshot: WidgetSnapshot) -> some View {
        let look = snapshot.look
        return self
            .foregroundStyle(look.ink.color)
            .fontDesign(look.fontDesign)
            .fontWidth(look.fontWidth)
            .tint(look.accent.color)
            .environment(\.colorScheme, look.isLight ? .light : .dark)
            .containerBackground(for: .widget) {
                ZStack {
                    LinearGradient(colors: [look.surface.color, look.ground.color],
                                   startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [look.accent.color.opacity(0.22), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: 220)
                    RadialGradient(colors: [look.accent2.color.opacity(0.12), .clear],
                                   center: .bottomLeading, startRadius: 0, endRadius: 200)
                }
            }
    }
}
