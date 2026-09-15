import SwiftUI
import UniformTypeIdentifiers

/// The things you kept — the Mac's two favourites drawers, as one tab with two sections.
struct HomeView: View {
    @Bindable var model: AppModel

    private enum Shelf: String, CaseIterable, Identifiable {
        case videos = "Videos"
        case channels = "Channels"
        var id: String { rawValue }
    }

    @State private var shelf: Shelf = .channels
    @State private var importing: UTType?
    @State private var exporting: URL?
    @State private var settingUpMinorMode = false
    @State private var settingUpFamily = false
    @State private var sendingToDevice = false
    @State private var unlocking = false

    var body: some View {
        NavigationStack(path: $model.homePath) {
            VStack(spacing: 0) {
                Picker("Shelf", selection: $shelf) {
                    ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 8)

                switch shelf {
                case .channels: channels
                case .videos: videos
                }
            }
            .navigationDestination(for: Channel.self) { channel in
                ChannelView(model: model, channel: channel)
            }
            .ground()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { menu }
            .fileImporter(
                isPresented: Binding(get: { importing != nil },
                                     set: { if !$0 { importing = nil } }),
                allowedContentTypes: importing.map { [$0] } ?? [.data],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                if importing == .commaSeparatedText {
                    model.importTakeout(from: url)
                } else {
                    // Reads the file and puts the choice on screen; nothing is merged
                    // until the sheet's own button.
                    model.offerImport(from: url)
                }
            }
            .sheet(item: $model.pendingImport) { pending in
                ImportSheet(model: model, pending: pending)
            }
            .sheet(item: $exporting) { url in ShareSheet(items: [url]) }
            .sheet(isPresented: $settingUpMinorMode) { MinorModeView(model: model) }
            .sheet(isPresented: $settingUpFamily) { FamilyView(model: model) }
            .onChange(of: model.wantsFamilySetup) { _, wants in
                if wants {
                    model.wantsFamilySetup = false
                    settingUpFamily = true
                }
            }
            .sheet(isPresented: $sendingToDevice) { SendSheet(model: model) }
            // Full screen rather than a sheet: a sheet can be swiped away, and a lock
            // you dismiss by flicking it downwards is not one. Cancel is the way out.
            .fullScreenCover(isPresented: $unlocking) {
                PINPad(profiles: model.profiles,
                       purpose: .unlock,
                       onDone: { unlocking = false },
                       onCancel: { unlocking = false })
            }
        }
    }

    private var channels: some View {
        Group {
            if model.library.channels.isEmpty {
                Placeholder(icon: "bookmark", title: "No channels yet",
                            detail: model.isMinor
                                ? "Channels added by a parent will show up here."
                                : "Bookmark a channel to keep it here, or import your "
                                    + "YouTube subscriptions from a Takeout export.")
            } else {
                List {
                    ForEach(model.library.recent) { channel in
                        HStack(spacing: 0) {
                            NavigationLink(value: channel) {
                                ChannelRow(channel: channel, isSaved: true)
                            }
                            ShelfMenu(model: model, channel: channel)
                        }
                        .listRowBackground(Color.card)
                    }
                    .onDelete(perform: removeChannels)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// Whether the library exists anywhere other than this phone, in the fewest words
    /// that are still true.
    private var cloudStatus: String {
        if let problem = model.library.cloud.problem { return problem }
        return model.library.cloud.hasSynced ? "Saved to iCloud" : "Checking iCloud…"
    }

    /// Nil in Minor Mode, which is what takes the swipe-to-delete off the rows: the shelf
    /// is the parent's curation and not the minor's to edit.
    private var removeChannels: ((IndexSet) -> Void)? {
        guard !model.isMinor else { return nil }
        return { offsets in
            let recent = model.library.recent
            for index in offsets { model.library.remove(recent[index].id) }
        }
    }

    private var videos: some View {
        Group {
            if model.library.videos.isEmpty {
                Placeholder(icon: "bookmark", title: "No saved videos",
                            detail: "Open a channel and swipe a video right to keep it "
                                + "here for later.")
            } else {
                List {
                    ForEach(model.library.videos) { video in
                        HStack(spacing: 0) {
                            Button { model.play(video) } label: {
                                VideoRow(video: video, isSaved: true, showChannel: true)
                            }
                            .buttonStyle(.plain)
                            ShelfMenu(model: model, video: video)
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
                    }
                    .onDelete { offsets in
                        let all = model.library.videos
                        for index in offsets { model.library.removeVideo(all[index].id) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// Importing, exporting and Minor Mode itself are all the parent's. In Minor Mode the
    /// whole menu is replaced by the one thing a minor's phone needs to offer: a way for
    /// the parent to get back in, which costs a PIN to use and is therefore safe to
    /// leave in plain sight.
    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if model.isMinor {
                Button("Minor Mode is on", systemImage: "lock.fill") { unlocking = true }
                    .labelStyle(.iconOnly)
                    .tint(Palette.accent)
            } else {
                Menu {
                    // The header says whether there is a copy anywhere but this phone.
                    // Worth the line: an app that silently is not backing up is worse
                    // than one that never claimed to, and this is the only place the
                    // question comes up.
                    Section(cloudStatus) {
                    // A submenu rather than three flat rows: you already know what is in
                    // your own library, so the choice can be made before the file exists.
                    // Importing is the other way round and asks afterwards — see
                    // `ImportSheet`.
                    Menu("Export Library", systemImage: "square.and.arrow.up") {
                        ForEach(Library.Contents.allCases) { contents in
                            Button(contents.menuLabel, systemImage: contents.icon) {
                                exporting = try? model.exportLibrary(contents)
                            }
                            .disabled(!model.library.canExport(contents))
                        }
                    }
                    Button("Import Library…", systemImage: "tray.and.arrow.down") {
                        importing = .ytcsLibrary
                    }
                    Button("Import YouTube Subscriptions…", systemImage: "square.and.arrow.down") {
                        importing = .commaSeparatedText
                    }
                    Button("Send to Device…", systemImage: "paperplane") {
                        sendingToDevice = true
                    }
                    .disabled(model.library.isEmpty && model.library.videos.isEmpty)
                    }

                    Divider()

                    Button("Family…", systemImage: "person.2") {
                        settingUpFamily = true
                    }
                    Button("Minor Mode…", systemImage: "lock.shield") {
                        settingUpMinorMode = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
