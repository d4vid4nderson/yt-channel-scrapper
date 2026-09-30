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
                if model.isMinor && model.childWasRemoved {
                    Placeholder(icon: "person.crop.circle.badge.xmark",
                                title: "This phone is not set up any more",
                                detail: "It was removed from the family. A parent can set "
                                    + "it up again from Command Center on the Mac.")
                } else {
                    if model.isMinor && model.shelf.folder == nil {
                        ConnectFolderCard(model: model)
                    }
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

    /// Nil in Minor Mode, for the same reason as `removeChannels`.
    private var removeVideos: ((IndexSet) -> Void)? {
        guard !model.isMinor else { return nil }
        return { offsets in
            let all = model.savedVideos
            for index in offsets { model.library.removeVideo(all[index].id) }
        }
    }

    private var videos: some View {
        Group {
            if model.savedVideos.isEmpty {
                Placeholder(icon: "bookmark", title: "No saved videos",
                            detail: model.isMinor
                                ? "Videos a parent adds will show up here."
                                : "Open a channel and swipe a video right to keep it "
                                    + "here for later.")
            } else {
                List {
                    ForEach(model.savedVideos) { video in
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
                    .onDelete(perform: removeVideos)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// Importing, exporting and Minor Mode itself are all the parent's. In Minor Mode the
    /// whole menu is replaced by the one thing a minor's phone needs to offer: a way for
    /// the parent to get back in, which costs a PIN to use and is therefore safe to
    /// leave in plain sight. The theme is the exception, offered alongside it: it is
    /// per phone, touches nothing a parent decided, and is the child's to pick.
    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        if model.isMinor {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    themePicker
                } label: {
                    Label("Theme", systemImage: "paintpalette")
                }
            }
        }
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

                    // A child's phone that a parent has unlocked to manage: one tap to
                    // hand it back, without going through the family list again.
                    if model.profiles.hasPIN, let last = model.profiles.lastMinor {
                        Button("Back to Minor Mode for \(last.name)", systemImage: "lock.fill") {
                            if model.profiles.relock() { model.enterMinorMode() }
                        }
                    }
                    Button("Family…", systemImage: "person.2") {
                        settingUpFamily = true
                    }
                    Button("Minor Mode…", systemImage: "lock.shield") {
                        settingUpMinorMode = true
                    }

                    Divider()

                    // Per phone: a child's device can wear a different theme from the
                    // parent's, and nothing about it travels with the library.
                    Menu("Theme", systemImage: "paintpalette") { themePicker }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var themePicker: some View {
        Picker("Theme", selection: Bindable(ThemeStore.shared).selection) {
            ForEach(Theme.all) { theme in
                Text(theme.name).tag(theme.id)
            }
        }
    }
}

/// The one step a child's phone cannot be given from the Mac: pointing it at the family
/// folder. iOS only lets an app into a shared iCloud Drive folder that the person holding
/// the phone picked.
///
/// Offered in Minor Mode, without the PIN, only while no folder is connected — which is
/// the moment a parent has just set the phone up and is still holding it. Once a folder
/// is connected this is gone, and changing it means unlocking first: a child picking some
/// other folder would read as a shelf with nothing on it.
private struct ConnectFolderCard: View {
    @Bindable var model: AppModel
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.person.crop")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect the family folder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                    Text(model.expectedFolderName.map { "Choose “\($0)” in iCloud Drive" }
                         ?? "Choose the folder a parent shared with this phone")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Color.secondaryText)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            guard !model.isOwnFolder(url) else {
                model.banner = "That is this app's own folder. Choose the family folder in iCloud Drive."
                return
            }
            if model.shelf.adopt(url) {
                model.expectedFolderName = nil
                Task { await model.syncShelf() }
            }
        }
    }
}
