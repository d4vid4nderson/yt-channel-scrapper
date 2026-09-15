import SwiftUI

/// What you keep, on the left; who you keep it for, on the right.
///
/// Channels and saved videos share the left panel as two collapsible sections — they are
/// both "things I have kept" and they were never big enough to need an edge each. That
/// freed the right edge for the family panel, which is the half of a command center that
/// says who is on the other end.
///
/// The landing screen's shelf already shows six saved channels, but it is a landing-screen
/// thing — it goes with the hero the moment a list is on screen, and it was never going to
/// hold a Takeout import of two hundred. The drawers are the whole library, reachable from
/// anywhere in the app, and they close again the instant you have what you came for.

// MARK: - Channels, on the left

struct SavedChannelsDrawer: View {
    /// Remembered across launches: whichever half somebody actually uses should be the
    /// one open when the panel comes back.
    @AppStorage("drawer.channels.open") private var channelsOpen = true
    @AppStorage("drawer.videos.open") private var videosOpen = true

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
                // Below a handful there is nothing to search for, and the field would
                // only be a row of chrome over a list you can already see all of.
                if model.library.channels.count > 6 {
                    DrawerFilterField(text: $filter, prompt: "Filter channels…")
                }
                Divider().overlay(.white.opacity(0.09))
                list
                Divider().overlay(.white.opacity(0.09))
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

    /// Both halves of the library in one panel, each able to fold away.
    ///
    /// They were two drawers on two edges, which gave each a whole screen edge for a list
    /// that is usually a dozen rows. Folding one shows more of the other, and the state
    /// sticks, so whichever half you actually use stays open.
    @ViewBuilder
    private var list: some View {
        if model.library.channels.isEmpty && model.library.videos.isEmpty {
            DrawerEmpty(
                icon: "bookmark",
                title: "Nothing saved yet",
                detail: "Bookmark a channel — in a search result, or above its video list — and it lands here."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                    Section {
                        if channelsOpen { channelRows }
                    } header: {
                        SectionBar(title: "Channels",
                                   count: model.library.channels.count,
                                   isOpen: $channelsOpen)
                    }

                    Section {
                        if videosOpen { videoRows }
                    } header: {
                        SectionBar(title: "Videos",
                                   count: model.library.videos.count,
                                   isOpen: $videosOpen)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
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
                // Drag a channel onto somebody in Dispatch to send it. The payload
                // carries the title so the receiving device never has to ask YouTube.
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
                    preview: { model.preview.open(video) },
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

/// A section's title line, and the thing that folds it.
///
/// Pinned, so the heading you are under stays on screen while its list scrolls past —
/// which is the only way to know which half you are looking at once both are long.
private struct SectionBar: View {
    let title: String
    let count: Int
    @Binding var isOpen: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.55))
            .padding(.vertical, 8)
            .padding(.top, 6)
            .contentShape(Rectangle())
            .background(Palette.ground)
        }
        .buttonStyle(.plain)
        .pointingHand()
    }
}

private struct SectionEmpty: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

private struct DrawerChannelRow: View {
    let channel: Channel
    let open: () -> Void
    let remove: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                ChannelAvatar(channel: channel, size: 34)
                    .overlay {
                        Circle().strokeBorder(
                            hovering ? Palette.accent.opacity(0.65) : .white.opacity(0.14),
                            lineWidth: 1
                        )
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(hovering ? 1 : 0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !channel.shelfSubtitle.isEmpty {
                        Text(channel.shelfSubtitle)
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.40))
                            .lineLimit(1)
                    }
                }

                // Held open whether or not the cursor is here, so the title does not
                // reflow under the button the moment you reach for it.
                Spacer(minLength: 26)
            }
            .padding(.horizontal, 10)
            .frame(height: 54)
            .background(Palette.tileSurface(active: hovering))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(hovering ? 0.16 : 0.075), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("List \(channel.title)'s videos")
        .pointingHand()
        // Outside the label, not inside it: a button nested in another button's label
        // does not reliably get the click.
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
}

private struct DrawerVideoRow: View {
    let video: Video
    let preview: () -> Void
    let download: () -> Void
    let remove: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: preview) {
            HStack(spacing: 10) {
                thumbnail

                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(hovering ? 1 : 0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // The drawer mixes channels the way the saved list does, so every row
                    // has to say where it came from.
                    Text(video.metaText(showingChannel: true))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.40))
                        .lineLimit(1)
                }

                Spacer(minLength: 52)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(minHeight: 66)
            .background(Palette.tileSurface(active: hovering))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(hovering ? 0.16 : 0.075), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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

    private var thumbnail: some View {
        AsyncImage(url: video.thumbnail) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(.white.opacity(0.06))
            }
        }
        .frame(width: 84, height: 84 * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if hovering {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !video.durationText.isEmpty {
                Text(video.durationText)
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 0.5)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
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
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(hovering ? Color(red: 1, green: 0.13, blue: 0.2) : Palette.accent)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(white: 0.78))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.09), in: Capsule())
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
                .foregroundStyle(.white.opacity(0.4))
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(prompt)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.32))
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Clear the filter")
                .pointingHand()
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(.white.opacity(0.07), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.09), lineWidth: 1)
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
                .foregroundStyle(Color(white: 0.45))
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color(white: 0.78))
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(Color(white: 0.45))
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
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
            .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.6))
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
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04))
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
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.5))
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
            .background(.black.opacity(0.75), in: Capsule())
    }
}
