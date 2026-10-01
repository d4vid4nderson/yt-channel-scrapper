import SwiftUI

/// What you keep, on the left; who you keep it for, on the right.
///
/// Channels and saved videos share the left panel as two tabs — they are both "things I
/// have kept" and they were never big enough to need an edge each. That
/// freed the right edge for the family panel, which is the half of a command center that
/// says who is on the other end.
///
/// The landing screen's shelf already shows six saved channels, but it is a landing-screen
/// thing — it goes with the hero the moment a list is on screen, and it was never going to
/// hold a Takeout import of two hundred. The drawers are the whole library, reachable from
/// anywhere in the app, and they close again the instant you have what you came for.

// MARK: - Channels, on the left

struct SavedChannelsDrawer: View {
    enum Tab: String, CaseIterable { case channels, videos }

    /// Remembered across launches: whichever half somebody actually uses should be the
    /// one showing when the panel comes back.
    @AppStorage("drawer.saved.tab") private var tab: Tab = .channels

    @Bindable var model: AppModel

    @State private var filter = ""
    @State private var targeted = false
    /// The order the list had when the panel opened. Opening a channel makes it the most
    /// recent one, which would otherwise slide it to the top from under the cursor — and
    /// now that the panel stays open, that would happen on every click, with a different
    /// channel landing under your hand each time. So the order is taken once, on opening,
    /// and held until you close it and come back.
    @State private var order: [String] = []

    private func close() { model.showChannelsDrawer = false }

    /// Most recently reached for first — the shelf's order, for the same reason: a list
    /// you scan is better led by what you actually use than by the alphabet.
    private var matches: [Channel] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let all = held(model.library.recent)
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.title.lowercased().contains(needle)
                || ($0.handle?.lowercased().contains(needle) ?? false)
        }
    }

    /// Recency, as it stood when the panel opened. Anything that has arrived since — a
    /// channel just bookmarked, an import — is not in the held order and goes to the top,
    /// which is where recency would have put it anyway.
    private func held(_ channels: [Channel]) -> [Channel] {
        guard !order.isEmpty else { return channels }
        var rank: [String: Int] = [:]
        for (index, id) in order.enumerated() { rank[id] = index }
        return channels.enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element.id] ?? -1
                let right = rank[rhs.element.id] ?? -1
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    var body: some View {
        SideDrawer(side: .leading, isPresented: $model.showChannelsDrawer) {
            VStack(spacing: 0) {
                DrawerHead(
                    title: "Saved",
                    count: model.library.channels.count + model.library.videos.count,
                    close: close
                )
                tabs
                // Below a handful there is nothing to search for, and the field would
                // only be a row of chrome over a list you can already see all of.
                if (tab == .channels ? model.library.channels.count : model.library.videos.count) > 6 {
                    DrawerFilterField(text: $filter,
                                      prompt: tab == .channels ? "Filter channels…" : "Filter videos…")
                }
                Divider().overlay(Palette.ink(0.09))
                list
                Divider().overlay(Palette.ink(0.09))
                if let note = model.library.note {
                    DrawerNote(text: note) { model.library.report(nil) }
                }
                HStack(spacing: 0) {
                    DrawerFooterButton(
                        icon: "square.and.arrow.down",
                        title: "Import subscriptions…",
                        action: model.importSubscriptions
                    )
                    .help("Merge a Google Takeout subscriptions.csv into your saved channels")

                    Spacer(minLength: 0)

                    // Moving Macs is a rare, deliberate act, so it sits behind a menu
                    // rather than taking a permanent row of its own.
                    LibraryMenu(model: model)
                }
            }
            // The same drop the shelf takes, in the panel that has now become the place
            // those channels live.
            .dropDestination(for: URL.self) { urls, _ in
                if let library = urls.first(where: {
                    $0.pathExtension.lowercased() == LibraryArchive.fileExtension
                }) {
                    model.importLibrary(from: library)
                    return true
                }
                guard let csv = urls.first(where: { $0.pathExtension.lowercased() == "csv" })
                else { return false }
                model.importSubscriptions(from: csv)
                return true
            } isTargeted: { targeted = $0 }
            .overlay {
                if targeted {
                    Palette.accent.opacity(0.10).allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.14), value: targeted)
            .onChange(of: model.showChannelsDrawer, initial: true) { _, open in
                if open { order = model.library.recent.map(\.id) }
            }
        }
    }

    /// Channels or videos, one at a time, each with its count. A tab rather than two
    /// folding sections: with a long list of channels the videos were a scroll away, and
    /// it was never clear which half you were in.
    private var tabs: some View {
        ChromeSegmented(
            options: Tab.allCases,
            selection: tab,
            label: { option in
                switch option {
                case .channels: "Channels  \(model.library.channels.count)"
                case .videos:   "Videos  \(model.library.videos.count)"
                }
            },
            help: { $0 == .channels ? "Your saved channels" : "Your saved videos" },
            pick: { tab = $0; filter = "" }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 13)
    }

    @ViewBuilder
    private var list: some View {
        let empty = tab == .channels ? model.library.channels.isEmpty : model.library.videos.isEmpty
        if empty {
            DrawerEmpty(
                icon: "bookmark",
                title: tab == .channels ? "No saved channels yet" : "No saved videos yet",
                detail: tab == .channels
                    ? "Bookmark a channel — in a search result, or above its video list — and it lands here."
                    : "Bookmark a video in the player and it lands here."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    switch tab {
                    case .channels: channelRows
                    case .videos:   videoRows
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.visible)
        }
    }

    @ViewBuilder
    private var channelRows: some View {
        if model.library.channels.isEmpty {
            SectionEmpty(text: "No saved channels.")
        } else if matches.isEmpty {
            SectionEmpty(text: "No saved channel is called “\(filter)”.")
        } else {
            ForEach(matches) { channel in
                DrawerChannelRow(
                    channel: channel,
                    // The panel stays where it is. Opening a channel is rarely the last
                    // thing you do in here — you came to look through what you have kept
                    // — and a list that shuts itself the moment you touch it makes you
                    // fetch it back for every channel you try.
                    open: { model.open(channel) },
                    remove: { model.library.remove(channel.id) }
                )
                // Drag onto somebody in Dispatch to send it. The payload carries the
                // title so the receiving device never has to ask YouTube anything.
                .onDrag {
                    NSItemProvider(object: SendPayload(
                        kind: .channel, id: channel.id,
                        title: channel.title, channelID: nil
                    ).encoded as NSString)
                } preview: {
                    DragChip(title: channel.title, icon: "person.crop.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var videoRows: some View {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let videos = needle.isEmpty
            ? model.library.videos
            : model.library.videos.filter { $0.title.lowercased().contains(needle) }
        if videos.isEmpty {
            SectionEmpty(text: needle.isEmpty
                         ? "No saved videos."
                         : "No saved video matches “\(filter)”.")
        } else {
            ForEach(videos) { video in
                DrawerVideoRow(
                    video: video,
                    preview: { model.openCard(video) },
                    download: { model.download([video]) },
                    remove: { model.library.removeVideo(video.id) }
                )
                .onDrag {
                    NSItemProvider(object: SendPayload(
                        kind: .video, id: video.id,
                        title: video.title, channelID: video.channelId
                    ).encoded as NSString)
                } preview: {
                    DragChip(title: video.title, icon: "play.rectangle")
                }
            }
        }
    }
}

private struct SectionEmpty: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Palette.ink(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

private struct DrawerChannelRow: View {
    let channel: Channel
    let open: () -> Void
    let remove: () -> Void

    @State private var hovering = false

    // Not a `Button`. On macOS a button consumes the press, so a drag started on one
    // never fires — these rows could be clicked but not dragged, which is now half of
    // what they are for. A tap gesture coexists with a drag; a button does not. The
    // nested buttons in the hover overlay still take their own clicks, because a real
    // Button outranks a parent's tap gesture.
    var body: some View {
        card
            .contentShape(ThemedRect(cornerRadius: 12, style: .continuous, seed: Torn.seed(channel.id)))
            .onTapGesture(perform: open)
            .help("List \(channel.title)'s videos")
            .pointingHand()
            .overlay(alignment: .trailing) {
                if hovering {
                    RemoveButton(action: remove)
                        .help("Remove \(channel.title) from your saved channels")
                        .padding(.trailing, 8)
                        .transition(.opacity)
                }
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private var card: some View {
        HStack(spacing: 10) {
                ChannelAvatar(channel: channel, size: 30)
                    .overlay {
                        Circle().strokeBorder(
                            hovering ? Palette.accent.opacity(0.65) : Palette.ink(0.14),
                            lineWidth: 1
                        )
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.ink(hovering ? 1 : 0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !channel.shelfSubtitle.isEmpty {
                        Text(channel.shelfSubtitle)
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(Palette.ink(0.40))
                            .lineLimit(1)
                    }
                }

                // Held open whether or not the cursor is here, so the title does not
                // reflow under the button the moment you reach for it.
                Spacer(minLength: 26)
            }
            .padding(.horizontal, 9)
            .frame(height: 46)
            .background(Palette.tileSurface(active: hovering))
            .clipShape(ThemedRect(cornerRadius: 12, style: .continuous, seed: Torn.seed(channel.id)))
            .overlay {
                ThemedRect(cornerRadius: 12, style: .continuous, seed: Torn.seed(channel.id))
                    .strokeBorder(Palette.ink(hovering ? 0.16 : 0.075), lineWidth: 1)
            }
            .themeEdge(radius: 12, lit: hovering, seed: Torn.seed(channel.id), quiet: true)
    }
}

private struct DrawerVideoRow: View {
    let video: Video
    let preview: () -> Void
    let download: () -> Void
    let remove: () -> Void

    @State private var hovering = false

    // Not a `Button`. On macOS a button consumes the press, so a drag started on one
    // never fires — these rows could be clicked but not dragged, which is now half of
    // what they are for. A tap gesture coexists with a drag; a button does not. The
    // nested buttons in the hover overlay still take their own clicks, because a real
    // Button outranks a parent's tap gesture.
    var body: some View {
        card
            .contentShape(ThemedRect(cornerRadius: 12, style: .continuous, seed: Torn.seed(video.id)))
            .onTapGesture(perform: preview)
            .help("Preview “\(video.title)”")
            .pointingHand()
            .overlay(alignment: .trailing) {
                if hovering {
                    HStack(spacing: 6) {
                        DownloadDot(action: download)
                            .help("Download just this video")
                        RemoveButton(action: remove)
                            .help("Remove this video from your saved videos")
                    }
                    .padding(.trailing, 8)
                    .transition(.opacity)
                }
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private var card: some View {
        HStack(spacing: 10) {
            thumbnail

                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink(hovering ? 1 : 0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // The drawer mixes channels the way the saved list does, so every row
                    // has to say where it came from.
                    Text(video.metaText(showingChannel: true))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.ink(0.40))
                        .lineLimit(1)
                }

                Spacer(minLength: 52)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .background(Palette.tileSurface(active: hovering))
            .clipShape(ThemedRect(cornerRadius: 12, style: .continuous, seed: Torn.seed(video.id)))
            .overlay {
                ThemedRect(cornerRadius: 12, style: .continuous, seed: Torn.seed(video.id))
                    .strokeBorder(Palette.ink(hovering ? 0.16 : 0.075), lineWidth: 1)
            }
            .themeEdge(radius: 12, lit: hovering, seed: Torn.seed(video.id), quiet: true)
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private var thumbnail: some View {
        AsyncImage(url: video.thumbnail) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(Palette.ink(0.06))
            }
        }
        .frame(width: 84, height: 84 * 9 / 16)
        .clipShape(ThemedRect(cornerRadius: 8, style: .continuous))
        .overlay {
            if hovering {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.onFill)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
                .clipShape(ThemedRect(cornerRadius: 8, style: .continuous))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !video.durationText.isEmpty {
                Text(video.durationText)
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    // White on the scrim in every theme: the scrim is black over a
                    // photograph, and a theme's onFill can be near-black.
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 0.5)
                    .background(.black.opacity(0.8), in: ThemedRect(cornerRadius: 3))
                    .padding(3)
            }
        }
    }
}

/// The row's fetch button — the list's red disc, at the size this panel works in.
private struct DownloadDot: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.onFill)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(hovering ? Palette.accentHot : Palette.accent)
                )
                .shadow(color: Palette.accent.opacity(hovering ? 0.65 : 0), radius: 7)
                .scaleEffect(hovering ? 1.1 : 1)
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

// MARK: - Shared furniture

/// The panel's title line, used by every drawer. Just the name and how many — which panel you are looking at is
/// already said by which edge it came in from, and by the lit button that opened it.
struct DrawerHead: View {
    let title: String
    let count: Int
    let close: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Text(title)
                .displayType(15, classic: .medium)
                .foregroundStyle(Palette.ink(1))
                .fixedSize()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Palette.ink(0.78))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Palette.ink(0.09), in: ThemedCapsule())
            }
            Spacer(minLength: 4)
            SheetButton(title: "Close", icon: "xmark", action: close)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 13)
    }
}

private struct DrawerFilterField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 10))
                .foregroundStyle(Palette.ink(0.4))
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(prompt)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink(0.32))
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink(1))
            }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink(0.4))
                }
                .buttonStyle(.plain)
                .help("Clear the filter")
                .pointingHand()
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Palette.ink(0.07), in: ThemedCapsule())
        .overlay {
            ThemedCapsule().strokeBorder(Palette.ink(0.09), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 13)
    }
}

/// Empty and no-match both land here: one shape, so the panel never changes size under
/// you as the filter narrows.
private struct DrawerEmpty: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Palette.ink(0.45))
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.ink(0.78))
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink(0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The one action at the foot of each panel. Quiet at rest, the way the shelf's own text
/// buttons are — it must not compete with the list above it.
private struct DrawerFooterButton: View {
    let icon: String
    let title: String
    var hint = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 6)
                if !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.ink(0.28))
                }
            }
            .foregroundStyle(Palette.ink(hovering ? 0.9 : 0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}


/// What the last import or export did.
///
/// The landing shelf used to carry this line and went with it; without somewhere to say
/// "imported 184 channels", an import is a file dialog closing and nothing else visibly
/// happening, which reads as failure.
struct DrawerNote: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.ink(0.45))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.ink(0.04))
    }
}

/// Carrying the library somewhere else, and bringing one back.
private struct LibraryMenu: View {
    @Bindable var model: AppModel
    @State private var hovering = false

    var body: some View {
        Menu {
            Button("Export Library…") { model.exportLibrary() }
                .disabled(model.library.isEmpty && model.library.videos.isEmpty)
            Button("Import Library…") { model.importLibrary() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink(hovering ? 0.9 : 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.trailing, 16)
        .help("Move your saved channels and videos to another Mac")
        .pointingHand()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}


/// What follows the cursor while dragging something towards a person.
private struct DragChip: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: 220)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.75), in: ThemedCapsule())
    }
}
