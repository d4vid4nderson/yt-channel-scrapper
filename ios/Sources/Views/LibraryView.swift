import SwiftUI
import UniformTypeIdentifiers

/// The things you kept — the Mac's two favourites drawers, as one tab with two sections.
struct LibraryView: View {
    @Bindable var model: AppModel

    private enum Shelf: String, CaseIterable, Identifiable {
        case channels = "Channels"
        case videos = "Videos"
        var id: String { rawValue }
    }

    @State private var shelf: Shelf = .channels
    @State private var importing: UTType?
    @State private var exporting: URL?

    var body: some View {
        NavigationStack {
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
            .ground()
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { menu }
            .fileImporter(
                isPresented: Binding(get: { importing != nil },
                                     set: { if !$0 { importing = nil } }),
                allowedContentTypes: importing.map { [$0] } ?? [],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                if importing == .commaSeparatedText {
                    model.importTakeout(from: url)
                } else {
                    model.importLibrary(from: url)
                }
            }
            .sheet(item: $exporting) { url in ShareSheet(items: [url]) }
        }
    }

    private var channels: some View {
        Group {
            if model.library.channels.isEmpty {
                Placeholder(icon: "star", title: "No saved channels",
                            detail: "Star a channel to keep it here, or import your "
                                + "YouTube subscriptions from a Takeout export.")
            } else {
                List {
                    ForEach(model.library.recent) { channel in
                        Button { model.open(channel) } label: {
                            ChannelRow(channel: channel, isSaved: true)
                        }
                        .listRowBackground(Color.card)
                    }
                    .onDelete { offsets in
                        let recent = model.library.recent
                        for index in offsets { model.library.remove(recent[index].id) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var videos: some View {
        Group {
            if model.library.videos.isEmpty {
                Placeholder(icon: "bookmark", title: "No saved videos",
                            detail: "Swipe a video right to keep it for later.")
            } else {
                List {
                    ForEach(model.library.videos) { video in
                        Button { model.playing = video } label: {
                            VideoRow(video: video, isSaved: true, showChannel: true)
                        }
                        .listRowBackground(Color.card)
                        .swipeActions(edge: .trailing) {
                            Button { model.download([video]) } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                            .tint(Palette.accent)
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

    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Import YouTube Subscriptions…", systemImage: "square.and.arrow.down") {
                    importing = .commaSeparatedText
                }
                Button("Import Library…", systemImage: "tray.and.arrow.down") {
                    importing = .ytcsLibrary
                }
                Button("Export Library…", systemImage: "square.and.arrow.up") {
                    exporting = try? model.exportLibrary()
                }
                .disabled(model.library.isEmpty && model.library.videos.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}
