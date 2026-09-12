import SwiftUI

/// The main screen: search for a channel, then work through its videos.
///
/// The Mac puts the search, the results and three drawers in one 1020×700 window. A
/// phone cannot, so the drawers became the other two tabs and this screen is just the
/// one column — which is what it always wanted to be.
struct BrowseView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if model.listing.hasResults || model.listing.isLoading {
                    videoList
                } else if model.search.hasResults || model.search.isBusy {
                    channelList
                } else {
                    start
                }
            }
            .ground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .searchable(
                text: $model.urlText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Channel name, @handle or URL"
            )
            .onSubmit(of: .search) { model.submit() }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
    }

    private var title: String {
        if model.listing.channel != nil { return model.listing.tab.label }
        if model.search.hasResults { return "Channels" }
        return "Browse"
    }

    // MARK: - Start

    private var start: some View {
        Group {
            if let error = model.search.error ?? model.listing.error {
                Placeholder(icon: "exclamationmark.triangle", title: "That did not work",
                            detail: error)
            } else if model.library.isEmpty {
                Placeholder(
                    icon: "magnifyingglass",
                    title: "Find a channel",
                    detail: "Search for a name, or paste a channel URL or @handle."
                )
            } else {
                // Somewhere to start that is not an empty box: the channels you keep.
                List {
                    Section("Recent") {
                        ForEach(model.library.recent.prefix(12)) { channel in
                            Button { model.open(channel) } label: {
                                ChannelRow(channel: channel, isSaved: true)
                            }
                            .listRowBackground(Color.card)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Channel results

    private var channelList: some View {
        List {
            if model.search.isBusy {
                loadingRow
            }
            ForEach(model.search.results) { channel in
                Button { model.open(channel) } label: {
                    ChannelRow(channel: channel, isSaved: model.library.contains(channel.id))
                }
                .listRowBackground(Color.card)
                .swipeActions(edge: .trailing) {
                    Button {
                        model.library.toggle(channel)
                    } label: {
                        Label(model.library.contains(channel.id) ? "Unsave" : "Save",
                              systemImage: model.library.contains(channel.id) ? "star.slash" : "star")
                    }
                    .tint(Palette.accent)
                }
            }
            if let error = model.search.error, !model.search.isBusy {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Videos

    private var videoList: some View {
        VStack(spacing: 0) {
            if let channel = model.listing.channel {
                ChannelHeader(channel: channel, isSaved: model.isListedChannelSaved) {
                    model.toggleSavedChannel()
                }
                Divider().overlay(Color.hairline)
            }

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
    }

    private func row(for video: Video) -> some View {
        Button {
            if model.isSelecting {
                model.toggle(video)
            } else {
                model.playing = video
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
            Button { model.download([video]) } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .tint(Palette.accent)
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.listing.channel != nil || model.search.hasResults {
                Button("Home", systemImage: "house") { model.goHome() }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if model.listing.hasResults {
                Button(model.isSelecting ? "Done" : "Select") {
                    withAnimation {
                        model.isSelecting.toggle()
                        if !model.isSelecting { model.picked = [] }
                    }
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            QualityMenu(model: model)
        }
    }
}

/// The quality picker, as a menu rather than the Mac's hanging panel.
struct QualityMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            Picker("Quality", selection: $model.quality) {
                ForEach(Quality.menuOrder) { option in
                    Text(option.iosLabel).tag(option)
                }
            }
            if !model.quality.isAudioOnly {
                Toggle("Also save an m4a", isOn: $model.alsoAudio)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("Quality: \(model.formatLabel)")
    }
}
