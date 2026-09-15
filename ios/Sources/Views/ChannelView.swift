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
                model.library.toggle(channel)
            }
            Divider().overlay(Color.hairline)

            TabPicker(tab: Binding(
                get: { model.listing.tab },
                set: { model.listing.show($0) }
            ))
            .padding(.vertical, 8)

            List {
                ForEach(model.visible) { video in
                    row(for: video)
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

            if model.isSelecting && !model.picked.isEmpty {
                selectionBar
            }
        }
        .ground()
        .navigationTitle(model.listing.tab.label)
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
                // Nothing to pick a quality for once downloading is gone.
                if !model.isMinor { QualityMenu(model: model) }
            }
        }
        // Keyed on the id so that pushing a different channel re-opens rather than
        // showing the previous one's videos under the new one's header.
        .task(id: channel.id) { model.beginListing(channel) }
    }

    private func row(for video: Video) -> some View {
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
            .tint(Palette.accent)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background(Color.card)
        .overlay(alignment: .top) { Divider().overlay(Color.hairline) }
        .transition(.move(edge: .bottom))
    }
}
