import SwiftUI

/// What other people have sent to this device, and a way to keep it.
///
/// Only a guardian sees this. On a minor's device the shelf *is* the library — anything
/// sent is added on sync, because a child did not ask for any of it and a screen asking
/// them to accept what a parent already decided would be ceremony. Between adults it is a
/// suggestion, and a suggestion you cannot decline is not one.
///
/// Everything here is drawn from the shelf entries alone — an id, a title, and for a
/// video its channel. That is the whole point of carrying those three fields: this screen
/// works with no network, and makes no request to YouTube for anything it lists.
struct InboxView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var waiting: (channels: [Channel], videos: [Video]) { model.unclaimedSent }

    var body: some View {
        NavigationStack {
            Group {
                if model.inboxCount == 0 {
                    Placeholder(
                        icon: "tray",
                        title: "Nothing new",
                        detail: "When another admin sends you a channel or a video, it "
                            + "waits here until you keep it."
                    )
                } else {
                    list
                }
            }
            .ground()
            .navigationTitle("Sent to you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.inboxCount > 0 {
                        Button("Keep All") {
                            model.claimSent()
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            if !waiting.channels.isEmpty {
                Section {
                    ForEach(waiting.channels) { channel in
                        row(ChannelRow(channel: channel)) {
                            model.library.add(channel)
                        }
                    }
                } header: {
                    header("Channels")
                } footer: {
                    Text("Keeping a channel puts it on your Home shelf. It does not "
                         + "download anything.")
                }
            }

            if !waiting.videos.isEmpty {
                Section {
                    ForEach(waiting.videos) { video in
                        row(VideoRow(video: video, showChannel: true)) {
                            model.library.toggleVideo(video, channel: nil)
                        }
                    }
                } header: {
                    header("Videos")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// One row, with the single action it supports. Swipe rather than a button on every
    /// row: the list is read first and acted on second, and a column of Keep buttons
    /// would make it look like a form.
    private func row(_ content: some View, keep: @escaping () -> Void) -> some View {
        content
            .listRowBackground(Color.card)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(action: keep) {
                    Label("Keep", systemImage: "bookmark")
                }
                .tint(Palette.accent)
            }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .textCase(nil)
    }
}
