import SwiftUI

/// Pick exactly what goes to somebody else's phone, then hand it to the share sheet.
///
/// The Export Library menu sends halves of the library — all the channels, all the
/// videos, or both. This is the other axis: the specific six channels you are happy for
/// a nine-year-old to have, and nothing else. Same file format on the far side, so it
/// imports through the ordinary Import Library with no special case.
///
/// Deliberately a manual send rather than a sync. It works across different Apple IDs
/// today, which iCloud key-value storage cannot do — that store is per-account and
/// Family Sharing shares purchases, not app data.
struct SendSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var channelIDs: Set<String> = []
    @State private var videoIDs: Set<String> = []
    @State private var sending: URL?

    var body: some View {
        NavigationStack {
            List {
                if !model.library.channels.isEmpty { channels }
                if !model.library.videos.isEmpty { videos }
                if model.library.channels.isEmpty && model.library.videos.isEmpty {
                    Text("There is nothing saved to send yet.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                        .listRowBackground(Color.card)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ground()
            .navigationTitle("Send to Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        sending = try? model.exportSelection(channelIDs: channelIDs,
                                                             videoIDs: videoIDs)
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(isEmpty)
                }
            }
            // Dismissing only after the share sheet has been and gone, so backing out of
            // AirDrop leaves the selection intact rather than making you tick it again.
            .sheet(item: $sending, onDismiss: { dismiss() }) { url in
                ShareSheet(items: [url])
            }
            .safeAreaInset(edge: .bottom) { summary }
        }
    }

    private var isEmpty: Bool { channelIDs.isEmpty && videoIDs.isEmpty }

    // MARK: - Sections

    private var channels: some View {
        Section {
            ForEach(model.library.recent) { channel in
                Button {
                    toggle(channel.id, in: &channelIDs)
                } label: {
                    ChannelRow(channel: channel,
                               isPicked: channelIDs.contains(channel.id),
                               isSelecting: true)
                }
                .listRowBackground(Color.card)
            }
        } header: {
            header("Channels", picked: channelIDs.count,
                   all: model.library.channels.map(\.id), into: $channelIDs)
        } footer: {
            // The part a parent should decide with open eyes: a channel is a standing
            // grant, not a fixed list.
            Text("A channel gives them everything in it — including whatever it uploads "
                 + "next. A video gives them only that one video.")
        }
    }

    private var videos: some View {
        Section {
            ForEach(model.library.videos) { video in
                Button {
                    toggle(video.id, in: &videoIDs)
                } label: {
                    VideoRow(video: video,
                             isPicked: videoIDs.contains(video.id),
                             isSelecting: true,
                             showChannel: true)
                }
                .listRowBackground(Color.card)
            }
        } header: {
            header("Videos", picked: videoIDs.count,
                   all: model.library.videos.map(\.id), into: $videoIDs)
        }
    }

    /// A section title that also counts what is ticked and offers all-or-nothing.
    private func header(_ title: String, picked: Int, all: [String],
                        into set: Binding<Set<String>>) -> some View {
        HStack {
            Text(picked == 0 ? title : "\(title) · \(picked)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
            Spacer()
            Button(picked == all.count ? "None" : "All") {
                set.wrappedValue = picked == all.count ? [] : Set(all)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.accent)
        }
        .textCase(nil)
    }

    /// What is about to leave, kept where the thumb is rather than only in the header.
    @ViewBuilder
    private var summary: some View {
        if !isEmpty {
            Text("Sending \(Library.summary(channels: channelIDs.count, videos: videoIDs.count)).")
                .font(.footnote)
                .foregroundStyle(Color.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Divider().overlay(Color.hairline) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
}
