import ImageIO
import SwiftUI
import UIKit
import WidgetKit

/// Keeps the Home Screen widgets' `WidgetSnapshot` current.
///
/// Everything a widget shows is decided here, on the app's side, where the approval
/// rules already live: on a minor's phone the recent videos are only ever approved ones,
/// the channels are the ones Home shows, and the Search button is not offered. The
/// widget draws what it is given and nothing more.
///
/// Pictures are fetched here too and written beside the snapshot, because a widget has
/// a few seconds and a small memory budget to render in and no business on the network.
@MainActor
final class WidgetFeed {
    static let shared = WidgetFeed()

    /// What was played, newest first, so the widgets can say "recent" and mean it.
    /// On this phone only; nothing about it travels with the library.
    private struct Watched: Codable {
        var id: String
        var title: String
        var channelID: String?
        var channelName: String?
    }

    private static let historyKey = "widget.watched.v1"
    private static let shelfChannels = 12
    private static let shelfVideos = 12
    private static let historyLimit = 12

    private var history: [Watched] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.historyKey) else { return [] }
            return (try? JSONDecoder().decode([Watched].self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.historyKey)
        }
    }

    private var pending: Task<Void, Never>?
    /// Kept for `refreshNow`, which the widget's own buttons call with no model to hand.
    private weak var model: AppModel?

    /// Rebuild the snapshot from the model. Cheap to call often: calls within a second
    /// of each other collapse into one write.
    func update(from model: AppModel) {
        self.model = model
        record(model.playback.item)
        let (snapshot, pictures) = build(from: model)
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await Self.fetch(pictures)
            guard !Task.isCancelled else { return }
            Self.write(snapshot, keeping: Set(pictures.map(\.name)))
        }
    }

    /// Write at once, skipping the wait and the picture fetch — for a press of the
    /// widget's own play or skip button, which should show what it did straight away.
    /// Whatever pictures it names are already on disk from the last full update.
    func refreshNow() {
        guard let model else { return }
        pending?.cancel()
        let (snapshot, pictures) = build(from: model)
        Self.write(snapshot, keeping: Set(pictures.map(\.name)))
    }

    private func record(_ item: Playable?) {
        guard let item else { return }
        let id = item.video?.id ?? item.file?.videoID
        guard let id else { return }
        let entry = Watched(id: id, title: item.title,
                            channelID: item.video?.channelId,
                            channelName: item.video?.channelName ?? item.file?.subtitle)
        var list = history
        guard list.first?.id != id else { return }
        list.removeAll { $0.id == id }
        list.insert(entry, at: 0)
        history = Array(list.prefix(Self.historyLimit))
    }

    // MARK: - Building

    private struct Picture: Sendable {
        let name: String
        let source: URL
    }

    private func build(from model: AppModel) -> (WidgetSnapshot, [Picture]) {
        var pictures: [Picture] = []
        func picture(_ name: String, _ url: URL?) -> String? {
            guard let url else { return nil }
            pictures.append(Picture(name: name, source: url))
            return name
        }

        // On a minor's phone, only what may be played. The history can hold something
        // since withdrawn, and a widget offering it would be a tile that refuses to play.
        let approved = model.isMinor ? model.approvedIDs : nil
        func allowed(_ id: String) -> Bool { approved?.contains(id) ?? true }

        func videoItem(id: String, title: String, channelID: String?,
                       channelName: String?) -> WidgetSnapshot.Item {
            WidgetSnapshot.Item(
                id: id, title: title, subtitle: channelName,
                image: picture("v-\(id).jpg",
                               URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")),
                link: WidgetLink.video(id: id, title: title, channelID: channelID,
                                       channelName: channelName).url)
        }

        var nowPlaying: WidgetSnapshot.Item?
        let isPlaying = model.playback.current != nil
        if let item = model.playback.item {
            let id = item.video?.id ?? item.file?.videoID ?? item.id
            nowPlaying = WidgetSnapshot.Item(
                id: id, title: item.title, subtitle: item.video?.channelName ?? item.file?.subtitle,
                image: picture("v-\(id).jpg", item.artwork),
                link: WidgetLink.resume.url)
        }

        let watched = history.filter { allowed($0.id) }
        if nowPlaying == nil, let last = watched.first {
            nowPlaying = videoItem(id: last.id, title: last.title,
                                   channelID: last.channelID, channelName: last.channelName)
        }

        // What was watched, then what is on Home, until there are enough to fill the
        // largest widget.
        var seen = Set<String>()
        var videos: [WidgetSnapshot.Item] = []
        for entry in watched where seen.insert(entry.id).inserted {
            videos.append(videoItem(id: entry.id, title: entry.title,
                                    channelID: entry.channelID, channelName: entry.channelName))
        }
        for video in model.savedVideos where allowed(video.id) && seen.insert(video.id).inserted {
            videos.append(videoItem(id: video.id, title: video.title,
                                    channelID: video.channelId, channelName: video.channelName))
        }
        videos = Array(videos.prefix(8))

        let channels = model.library.recent.prefix(8).map { channel in
            WidgetSnapshot.Item(
                id: channel.id, title: channel.title, subtitle: channel.handle,
                image: picture("c-\(channel.id).jpg", channel.avatar),
                link: WidgetLink.channel(id: channel.id).url)
        }

        // What each channel can offer the widgets to browse. A minor's phone offers only
        // what was approved from it and never looks at the channel itself — the same rule
        // as `approvedVideos(of:)`. A parent's offers what they saved from it, then the
        // listing open in the app if it is that channel, then the first page of the
        // channel as `ChannelPages` last saw it.
        func offered(_ channelID: String) -> [Video] {
            if model.isMinor {
                return model.approvedVideos.filter { $0.channelId == channelID }
            }
            var seen = Set<String>()
            let saved = model.library.videos.filter { $0.channelId == channelID }
            let listed = model.listing.channel?.id == channelID ? model.listing.videos : []
            return (saved + listed + ChannelPages.shared.videos(for: channelID))
                .filter { seen.insert($0.id).inserted }
        }

        func shelf(id: String, title: String, handle: String?, avatar: URL?) -> WidgetSnapshot.Shelf {
            let videos = offered(id).prefix(Self.shelfVideos).map { video in
                let name = video.channelName ?? title
                return WidgetSnapshot.ShelfVideo(
                    item: videoItem(id: video.id, title: video.title,
                                    channelID: id, channelName: name),
                    channelID: id, channelName: name)
            }
            return WidgetSnapshot.Shelf(
                channel: WidgetSnapshot.Item(
                    id: id, title: title, subtitle: handle,
                    image: picture("c-\(id).jpg", avatar),
                    link: WidgetLink.channel(id: id).url),
                videos: Array(videos))
        }

        // The channel of what is playing, so the widgets can offer more from it — found
        // even when it is not one Home keeps, as long as the video says whose it is.
        var playingShelf: WidgetSnapshot.Shelf?
        if let item = model.playback.item {
            let currentID = item.video?.id ?? item.file?.videoID
            let video = item.video ?? model.savedVideos.first { $0.id == currentID }
            if let channelID = video?.channelId {
                let kept = model.library.channels.first { $0.id == channelID }
                playingShelf = shelf(id: channelID,
                                     title: kept?.title ?? video?.channelName ?? "This channel",
                                     handle: kept?.handle, avatar: kept?.avatar)
            }
        }

        let homeChannels = Array(model.library.recent.prefix(Self.shelfChannels))
        var shelves = homeChannels.map {
            shelf(id: $0.id, title: $0.title, handle: $0.handle, avatar: $0.avatar)
        }
        // What is playing comes first in Browse, wherever it sits on Home.
        if let playingShelf {
            shelves.removeAll { $0.id == playingShelf.id }
            shelves.insert(playingShelf, at: 0)
        }

        if !model.isMinor {
            let wanted = (playingShelf.map { [$0.id] } ?? []) + homeChannels.map(\.id)
            ChannelPages.shared.refresh(wanted) { [weak self, weak model] in
                guard let self, let model else { return }
                self.update(from: model)
            }
        }

        let progress = isPlaying ? NowPlaying.shared.position.map {
            WidgetSnapshot.Progress(elapsed: $0.elapsed, duration: $0.duration,
                                    isPaused: $0.isPaused, asOf: .now)
        } : nil
        let snapshot = WidgetSnapshot(
            nowPlaying: nowPlaying, isPlaying: isPlaying, progress: progress,
            repeatMode: RepeatSetting.shared.mode,
            videos: videos, channels: Array(channels), shelves: shelves,
            playingShelf: playingShelf,
            allowsSearch: !model.isMinor,
            look: Self.look(ThemeStore.shared.theme),
            themes: Theme.all.map { WidgetSnapshot.NamedLook(id: $0.id.rawValue, name: $0.name, look: Self.look($0)) })
        return (snapshot, pictures)
    }

    /// The theme, resolved to plain values for a process that has no `Theme`.
    private static func look(_ theme: Theme) -> WidgetSnapshot.Look {
        // Pinned to the appearance the app itself wears — dark unless the theme is light,
        // as `ThemedRoot` does — since the widget has nothing to resolve an adaptive
        // colour against that would agree with the app.
        let isLight = theme.colorScheme == .light
        let traits = UITraitCollection(userInterfaceStyle: isLight ? .light : .dark)
        func rgb(_ color: Color) -> WidgetSnapshot.RGB {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            return WidgetSnapshot.RGB(r: Double(r), g: Double(g), b: Double(b))
        }
        let corners: (String, Double) = switch theme.corners {
        case .rounded(let scale):   ("rounded", Double(scale))
        case .chamfered(let scale): ("chamfered", Double(scale))
        case .square:               ("square", 0)
        }
        let design = switch theme.type.design {
        case .serif: "serif"
        case .rounded: "rounded"
        case .monospaced: "monospaced"
        default: "default"
        }
        let width = switch theme.type.width {
        case .condensed: "condensed"
        case .compressed: "compressed"
        case .expanded: "expanded"
        default: "standard"
        }
        return WidgetSnapshot.Look(
            accent: rgb(theme.accent), accent2: rgb(theme.accent2),
            ground: rgb(theme.ground), surface: rgb(theme.surface), card: rgb(theme.card),
            ink: rgb(theme.ink), onFill: rgb(theme.onFill),
            design: design, width: width,
            displayFont: theme.type.displayName, displayCaps: theme.type.displayCaps,
            corners: corners.0, cornerScale: corners.1, isLight: isLight)
    }

    // MARK: - Writing

    /// Fetch whatever pictures are not already on disk, small enough for a widget.
    private nonisolated static func fetch(_ pictures: [Picture]) async {
        guard let folder = WidgetSnapshot.images else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await withTaskGroup(of: Void.self) { group in
            for picture in pictures {
                let destination = folder.appendingPathComponent(picture.name)
                guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
                group.addTask {
                    guard let (data, _) = try? await URLSession.shared.data(from: picture.source),
                          let small = shrink(data) else { return }
                    try? small.write(to: destination, options: .atomic)
                }
            }
        }
    }

    /// A widget refuses to draw an image over its size budget, so nothing larger than
    /// 400px on its long side goes in.
    private nonisolated static func shrink(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }

    private static func write(_ snapshot: WidgetSnapshot, keeping names: Set<String>) {
        // Only name pictures that actually arrived, so the widget draws a placeholder
        // rather than a hole for one that failed.
        var snapshot = snapshot
        func present(_ item: WidgetSnapshot.Item) -> WidgetSnapshot.Item {
            var item = item
            if let name = item.image, let url = WidgetSnapshot.imageURL(name),
               !FileManager.default.fileExists(atPath: url.path) {
                item.image = nil
            }
            return item
        }
        snapshot.nowPlaying = snapshot.nowPlaying.map(present)
        snapshot.videos = snapshot.videos.map(present)
        snapshot.channels = snapshot.channels.map(present)

        do {
            try snapshot.save()
        } catch {
            Log.library.error("widget snapshot: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Pictures nothing refers to any more.
        if let folder = WidgetSnapshot.images,
           let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for file in files where !names.contains(file) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// The first page of each saved channel, kept for the Browse widget on a parent's phone.
///
/// The app only ever reads a channel live, when you open it, and keeps nothing. A widget
/// browsing channels without opening the app needs *something* for each one, so this
/// fetches the first page of the channels Home lists — a few at a time, each at most every
/// six hours — and remembers it in Caches. Never used on a minor's phone, whose widget
/// offers approved videos and nothing else.
@MainActor
final class ChannelPages {
    static let shared = ChannelPages()

    private struct Page: Codable {
        var fetched: Date
        var videos: [Video]
    }

    private static let maxAge: TimeInterval = 6 * 60 * 60
    private static let file: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("widget-channel-pages.json")
    }()

    private var pages: [String: Page]
    private var running: Task<Void, Never>?

    private init() {
        pages = (try? Data(contentsOf: Self.file))
            .flatMap { try? JSONDecoder().decode([String: Page].self, from: $0) } ?? [:]
    }

    func videos(for channelID: String) -> [Video] { pages[channelID]?.videos ?? [] }

    /// Fetch whichever of these channels are missing or stale, then call `done` once if
    /// anything new arrived. One pass at a time; a call while one runs is dropped, and
    /// the next update picks up whatever it missed.
    func refresh(_ channelIDs: [String], done: @escaping @MainActor () -> Void) {
        guard running == nil else { return }
        let stale = channelIDs.filter {
            guard let page = pages[$0] else { return true }
            return Date().timeIntervalSince(page.fetched) > Self.maxAge
        }
        guard !stale.isEmpty else { return }
        running = Task { [weak self] in
            var changed = false
            for id in stale {
                guard !Task.isCancelled else { break }
                guard let page = try? await YouTubeAPI.listChannelTab(browseID: id, tab: .videos)
                else { continue }
                self?.pages[id] = Page(fetched: Date(), videos: Array(page.videos.prefix(12)))
                changed = true
            }
            guard let self else { return }
            self.running = nil
            // Channels no longer on Home go with the write.
            self.pages = self.pages.filter { channelIDs.contains($0.key) }
            if let data = try? JSONEncoder().encode(self.pages) {
                try? data.write(to: Self.file, options: .atomic)
            }
            if changed { done() }
        }
    }
}
