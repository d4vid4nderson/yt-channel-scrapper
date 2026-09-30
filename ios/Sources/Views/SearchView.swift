import SwiftUI

/// The main screen: search for a channel, then work through its videos.
///
/// The Mac puts the search, the results and three drawers in one 1020×700 window. A
/// phone cannot, so the drawers became the other two tabs and this screen is just the
/// one column — which is what it always wanted to be.
struct SearchView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack(path: $model.searchPath) {
            VStack(spacing: 0) {
                // Only once something has been searched for: an empty screen does not
                // need a filter on nothing.
                if !model.search.query.isEmpty {
                    Picker("Find", selection: Binding(
                        get: { model.search.scope },
                        set: { model.search.scope = $0 }
                    )) {
                        ForEach(ChannelSearch.Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 8)
                }

                Group {
                    if model.search.hasResults || model.search.isBusy {
                        switch model.search.scope {
                        case .channels: channelList
                        case .videos:   videoList
                        }
                    } else {
                        start
                    }
                }
            }
            .navigationDestination(for: Channel.self) { channel in
                ChannelView(model: model, channel: channel)
            }
            .ground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .searchable(
                text: $model.urlText,
                isPresented: $model.searchActive,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Video name, channel name, @handle or URL"
            )
            .onSubmit(of: .search) { model.submit() }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
    }

    private var title: String {
        model.search.hasResults ? model.search.scope.rawValue : "Search"
    }

    // MARK: - Start

    private var start: some View {
        Group {
            if let error = model.search.error ?? model.listing.error {
                Placeholder(icon: "exclamationmark.triangle", title: "That did not work",
                            detail: error)
            } else {
                Placeholder(
                    icon: "magnifyingglass",
                    title: "Find a video or a channel",
                    detail: "Search for a title or a name, or paste a channel URL or "
                        + "@handle. Bookmark either and it will be waiting on Home."
                )
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
                HStack(spacing: 0) {
                    NavigationLink(value: channel) {
                        ChannelRow(channel: channel, isSaved: model.library.contains(channel.id))
                    }
                    ShelfMenu(model: model, channel: channel)
                }
                .listRowBackground(Color.card)
                .swipeActions(edge: .trailing) {
                    Button {
                        model.library.toggle(channel)
                    } label: {
                        Label(model.library.contains(channel.id) ? "Unsave" : "Save",
                              systemImage: model.library.contains(channel.id) ? "bookmark.slash" : "bookmark")
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

    /// Shown while a search is in flight. `ChannelView` has its own copy for paging;
    /// they are three lines and sharing them would mean a file for the pair.
    /// Video results. Tapping plays; the channel is one swipe away, because finding a
    /// video is often how you find the channel worth keeping.
    private var videoList: some View {
        List {
            if model.search.isBusy {
                loadingRow
            }
            ForEach(model.search.videos) { video in
                HStack(spacing: 0) {
                    Button { model.play(video) } label: {
                        VideoRow(video: video, isSaved: model.isSaved(video), showChannel: true)
                    }
                    .buttonStyle(.plain)
                    ShelfMenu(model: model, video: video)
                }
                .listRowBackground(Color.card)
                .swipeActions(edge: .leading) {
                    if let channel = model.channel(of: video) {
                        Button { model.show(channel) } label: {
                            Label("Channel", systemImage: "person.crop.circle")
                        }
                        .tint(.indigo)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button { model.download([video]) } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .tint(Palette.accent)
                    Button { model.toggleSaved(video) } label: {
                        Label(model.isSaved(video) ? "Unsave" : "Save",
                              systemImage: model.isSaved(video) ? "bookmark.slash" : "bookmark")
                    }
                    .tint(.gray)
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

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView().tint(Color.secondaryText)
            Spacer()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.search.hasResults {
                Button("Clear", systemImage: "xmark") { model.clearSearch() }
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
