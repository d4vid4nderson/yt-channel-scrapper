import SwiftUI

/// One channel's videos.
///
/// This used to be a *mode* of `BrowseView`, entered by writing to `model.listing` and
/// reached only by whichever tab happened to be showing. Everything awkward about the
/// app's navigation came from that: opening a channel from Saved had to switch tabs to
/// be seen, Browse needed something to fill its idle state and borrowed the saved
/// channels list to do it, and two tabs ended up showing the same thing.
///
/// As a pushed screen it is reachable from anywhere, comes with a back button, and
/// leaves the list you came from exactly as you left it.
struct ChannelView: View {
    @Bindable var model: AppModel
    let channel: Channel

    var body: some View {
        VStack(spacing: 0) {
            ChannelHeader(channel: channel, isSaved: model.library.contains(channel.id)) {
                // The saved channels are the parent's curation, not the minor's to edit.
                if !model.isMinor { model.library.toggle(channel) }
            }
            Divider().overlay(Color.hairline)

            if model.isMinor {
                downloaded
            } else {
                TabPicker(tab: Binding(
                    get: { model.listing.tab },
                    set: { model.listing.show($0) }
                ))
                .padding(.top, 8)

                freshness
                    .padding(.vertical, 6)

                if let error = model.listing.error, !model.listing.hasResults {
                    Placeholder(icon: "exclamationmark.triangle", title: "Nothing to show",
                                detail: error)
                } else {
                    live
                }
            }

            if model.isSelecting && !model.picked.isEmpty {
                selectionBar
            }
        }
        .ground()
        .navigationTitle(model.isMinor ? channel.title : model.listing.tab.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.listing.hasResults && !model.isMinor {
                    Button(model.isSelecting ? "Done" : "Select") {
                        withAnimation {
                            model.isSelecting.toggle()
                            if !model.isSelecting { model.picked = [] }
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !model.isMinor {
                    Button {
                        Task { await model.listing.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.listing.isRefreshing)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Nothing to pick a quality for once downloading is gone.
                if !model.isMinor { QualityMenu(model: model) }
            }
        }
        // Keyed on the id so that pushing a different channel re-opens rather than
        // showing the previous one's videos under the new one's header.
        // A minor's phone never asks YouTube for the channel's catalogue at all.
        .task(id: channel.id) { if !model.isMinor { model.beginListing(channel) } }
    }

    private var live: some View {
        List {
            ForEach(model.visible) { video in
                row(for: video)
            }

            // The first read of a channel never seen before.
            if model.listing.isLoading && !model.listing.hasResults {
                loadingRow
            }

            // Reaching this row is what asks for the next page — no "load more"
            // button, because an infinite list is what a phone expects.
            if model.listing.continuation != nil {
                loadingRow
                    .onAppear { model.listing.loadMore() }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.default, value: model.isSelecting)
        .refreshable { await model.listing.refresh() }
    }

    /// When the list last heard from YouTube, since it is kept on the phone and opens
    /// without asking — and what the last refresh brought, so a pull that found nothing
    /// says so instead of looking like it did not happen.
    private var freshness: some View {
        HStack(spacing: 6) {
            if model.listing.isRefreshing {
                ProgressView().controlSize(.mini).tint(Color.secondaryText)
                Text("Checking for new videos…")
            } else if let refreshed = model.listing.refreshed {
                // Re-rendered each minute, so "just now" does not sit there for an hour.
                TimelineView(.everyMinute) { _ in
                    Text(Self.updated(refreshed) + Self.added(model.listing.added))
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 14)
    }

    private static func updated(_ date: Date) -> String {
        if Date.now.timeIntervalSince(date) < 60 { return "Updated just now" }
        return "Updated " + date.formatted(.relative(presentation: .named))
    }

    private static func added(_ count: Int?) -> String {
        switch count {
        case nil: ""
        case 0?: " · nothing new"
        case 1?: " · 1 new video"
        case let n?: " · \(n) new videos"
        }
    }

    /// Minor Mode's version of the channel: what has been approved from it, and nothing
    /// else.
    @ViewBuilder
    private var downloaded: some View {
        let videos = model.approvedVideos(of: channel)
        if videos.isEmpty {
            Placeholder(icon: "play.rectangle", title: "Nothing here yet",
                        detail: "Videos from this channel show up once a parent has "
                            + "added them.")
        } else {
            List {
                ForEach(videos) { video in
                    Button { model.play(video) } label: {
                        VideoRow(video: video, isSaved: true, showChannel: false)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.card)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(for video: Video) -> some View {
        HStack(spacing: 0) {
            Button {
                if model.isSelecting {
                    model.toggle(video)
                } else {
                    model.play(video)
                }
            } label: {
                VideoRow(
                    video: video,
                    isPicked: model.picked.contains(video.id),
                    isSelecting: model.isSelecting,
                    isSaved: model.isSaved(video),
                    // Every row here belongs to the channel named in the header above, so
                    // repeating it on each row would be noise.
                    showChannel: false
                )
            }
            .buttonStyle(.plain)
            // Hidden while selecting: the row's job is then the tick, and a menu that
            // acts on one video in the middle of choosing several is a mis-tap waiting
            // to happen.
            if !model.isSelecting {
                ShelfMenu(model: model, video: video)
            }
        }
        .listRowBackground(Color.card)
        .swipeActions(edge: .trailing) {
            if !model.isMinor {
                Button { model.download([video]) } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .tint(Palette.accent)
            }
        }
        .swipeActions(edge: .leading) {
            Button { model.toggleSaved(video) } label: {
                Label(model.isSaved(video) ? "Unsave" : "Save",
                      systemImage: model.isSaved(video) ? "bookmark.slash" : "bookmark")
            }
            .tint(.indigo)
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView().tint(Color.secondaryText)
            Spacer()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// The bar that appears once something is ticked, so the count and the action are
    /// where the thumb is rather than in the navigation bar.
    private var selectionBar: some View {
        HStack(spacing: 14) {
            Button(model.allVisiblePicked ? "None" : "All") { model.toggleAllVisible() }
                .foregroundStyle(Color.secondaryText)

            Spacer()

            Text("\(model.picked.count) selected")
                .font(.footnote)
                .foregroundStyle(Color.secondaryText)

            Button {
                model.downloadPicked()
            } label: {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            // The theme sets a default ink for the whole app, which would otherwise win over
            // the white a filled button gives its label — green on green on the Nostromo.
            .foregroundStyle(Palette.onFill)
            .tint(Palette.accent)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background(Color.card)
        .overlay(alignment: .top) { Divider().overlay(Color.hairline) }
        .transition(.move(edge: .bottom))
    }
}
