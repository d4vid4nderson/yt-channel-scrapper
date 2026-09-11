import SwiftUI

/// The two things you keep, on the two edges: channels on the left, videos on the right.
///
/// The landing screen's shelf already shows six saved channels, but it is a landing-screen
/// thing — it goes with the hero the moment a list is on screen, and it was never going to
/// hold a Takeout import of two hundred. The drawers are the whole library, reachable from
/// anywhere in the app, and they close again the instant you have what you came for.

// MARK: - Channels, on the left

struct SavedChannelsDrawer: View {
    @Bindable var model: AppModel

    @State private var filter = ""
    @State private var targeted = false

    private func close() { model.showChannelsDrawer = false }

    /// Most recently reached for first — the shelf's order, for the same reason: a list
    /// you scan is better led by what you actually use than by the alphabet.
    private var matches: [Channel] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let all = model.library.recent
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.title.lowercased().contains(needle)
                || ($0.handle?.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        SideDrawer(side: .leading, isPresented: $model.showChannelsDrawer) {
            VStack(spacing: 0) {
                DrawerHead(
                    title: "Saved channels",
                    count: model.library.channels.count,
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
                DrawerFooterButton(
                    icon: "square.and.arrow.down",
                    title: "Import subscriptions…",
                    hint: "or drop a .csv",
                    action: model.importSubscriptions
                )
                .help("Merge a Google Takeout subscriptions.csv into your saved channels")
            }
            // The same drop the shelf takes, in the panel that has now become the place
            // those channels live.
            .dropDestination(for: URL.self) { urls, _ in
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
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.library.channels.isEmpty {
            DrawerEmpty(
                icon: "bookmark",
                title: "No saved channels yet",
                detail: "Bookmark a channel — in a search result, or above its video list — and it lands here."
            )
        } else if matches.isEmpty {
            DrawerEmpty(
                icon: "magnifyingglass",
                title: "Nothing matches",
                detail: "No saved channel is called “\(filter)”."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(matches) { channel in
                        DrawerChannelRow(
                            channel: channel,
                            // Straight to its videos, and out of the way — the panel is
                            // over the list it just asked for.
                            open: { model.open(channel); close() },
                            remove: { model.library.remove(channel.id) }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.visible)
        }
    }
}

// MARK: - Videos, on the right

struct SavedVideosDrawer: View {
    @Bindable var model: AppModel

    @State private var filter = ""

    private func close() { model.showVideosDrawer = false }

    /// Newest first, the order the library keeps them in: a saved video is something you
    /// meant to come back to shortly.
    private var matches: [Video] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let all = model.library.videos
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.title.lowercased().contains(needle)
                || ($0.channelName?.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        SideDrawer(side: .trailing, isPresented: $model.showVideosDrawer) {
            VStack(spacing: 0) {
                DrawerHead(
                    title: "Saved videos",
                    count: model.library.videos.count,
                    close: close
                )
                if model.library.videos.count > 6 {
                    DrawerFilterField(text: $filter, prompt: "Filter videos…")
                }
                Divider().overlay(.white.opacity(0.09))
                list
                Divider().overlay(.white.opacity(0.09))
                // Watching and fetching one at a time is what the drawer is for; ticking
                // a dozen of them is what the main list is for, so that is one click away
                // rather than a second selection model in here.
                DrawerFooterButton(
                    icon: "list.bullet",
                    title: "Open as a list",
                    hint: "to pick several"
                ) {
                    model.showSavedVideos()
                    close()
                }
                .disabled(model.library.videos.isEmpty)
                .opacity(model.library.videos.isEmpty ? 0.4 : 1)
                .help("Show the saved videos in the main list, where they can be ticked and downloaded together")
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.library.videos.isEmpty {
            DrawerEmpty(
                icon: "bookmark",
                title: "No saved videos yet",
                detail: "Bookmark a video in any channel's list to keep it here — it stays after the scrape is gone."
            )
        } else if matches.isEmpty {
            DrawerEmpty(
                icon: "magnifyingglass",
                title: "Nothing matches",
                detail: "No saved video is called “\(filter)”."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(matches) { video in
                        DrawerVideoRow(
                            video: video,
                            preview: { model.preview.open(video) },
                            download: { model.download([video]) },
                            remove: { model.library.removeVideo(video.id) }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.visible)
        }
    }
}

// MARK: - Rows

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

/// The panel's title line. Just the name and how many — which panel you are looking at is
/// already said by which edge it came in from, and by the lit button that opened it.
private struct DrawerHead: View {
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
