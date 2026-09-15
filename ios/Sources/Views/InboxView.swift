import SwiftUI

/// What other people have sent to this device, and a way to keep it.
///
/// A tab on both kinds of device, doing a different job on each. For an admin it is a
/// queue: things another admin sent, waiting to be kept or ignored — between adults a
/// send is a suggestion, and a suggestion you cannot decline is not one. For a minor it
/// is a record: what has been sent is already on their shelves and already downloading,
/// because a child did not ask for any of it and a screen asking them to accept what a
/// parent already decided would be ceremony.
///
/// Everything here is drawn from the shelf entries alone — an id, a title, and for a
/// video its channel. That is the whole point of carrying those three fields: this screen
/// works with no network, and makes no request to YouTube for anything it lists.
struct InboxView: View {
    @Bindable var model: AppModel

    /// What is waiting to be kept — an admin's view.
    private var waiting: (channels: [Channel], videos: [Video]) { model.unclaimedSent }
    /// Everything ever sent here — a minor's view, since theirs is added automatically
    /// and a list of "things to accept" would always be empty.
    private var everything: (channels: [Channel], videos: [Video]) { model.sent }

    private var isMinor: Bool { model.isMinor }

    var body: some View {
        NavigationStack {
            Group {
                if isMinor {
                    minorList
                } else if model.inboxCount == 0 {
                    Placeholder(
                        icon: "tray",
                        title: "Nothing new",
                        detail: "When another admin sends you a channel or a video it waits "
                            + "here until you deal with it. Nothing downloads by itself."
                    )
                } else {
                    adminList
                }
            }
            .ground()
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !isMinor, model.inboxCount > 0 {
                        Button("Keep All") { model.claimSent() }
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .task { await model.syncShelf() }
        }
    }

    // MARK: - A minor's phone

    /// Read-only, and says so. There is nothing to accept: it is already on their
    /// shelves and the approved videos are already downloading.
    @ViewBuilder
    private var minorList: some View {
        if everything.channels.isEmpty && everything.videos.isEmpty {
            Placeholder(
                icon: "tray",
                title: "Nothing yet",
                detail: "Channels and videos a grown-up sends you will show up here, and "
                    + "on your Home shelves."
            )
        } else {
            List {
                if !everything.channels.isEmpty {
                    Section {
                        ForEach(everything.channels) { channel in
                            ChannelRow(channel: channel, isSaved: true)
                                .listRowBackground(Color.card)
                        }
                    } header: { header("Channels") }
                }
                if !everything.videos.isEmpty {
                    Section {
                        ForEach(everything.videos) { video in
                            Button { model.play(video) } label: {
                                VideoRow(video: video, isSaved: true, showChannel: true)
                            }
                            .listRowBackground(Color.card)
                        }
                    } header: { header("Videos") }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - An admin's phone

    private var adminList: some View {
        List {
            if !waiting.channels.isEmpty {
                Section {
                    ForEach(waiting.channels) { channel in
                        ChannelRow(channel: channel, isSaved: model.isKept(channel))
                            .listRowBackground(Color.card)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    model.dismiss(channel: channel)
                                } label: { Label("Remove", systemImage: "xmark") }

                                if !model.isKept(channel) {
                                    Button { model.library.add(channel) } label: {
                                        Label("Save", systemImage: "bookmark")
                                    }
                                    .tint(Palette.accent)
                                }
                            }
                    }
                } header: {
                    header("Channels")
                } footer: {
                    Text("Saving puts a channel on your Home shelf. Removing takes it off "
                         + "this list without changing anything for anybody else.")
                }
            }

            if !waiting.videos.isEmpty {
                Section {
                    ForEach(waiting.videos) { video in
                        Button { model.play(video) } label: {
                            VideoRow(video: video, isSaved: model.isKept(video),
                                     showChannel: true)
                        }
                        .listRowBackground(Color.card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.dismiss(video: video)
                            } label: { Label("Remove", systemImage: "xmark") }

                            Button { model.download([video]) } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                            .tint(.indigo)

                            if !model.isKept(video) {
                                Button { model.library.toggleVideo(video, channel: nil) } label: {
                                    Label("Save", systemImage: "bookmark")
                                }
                                .tint(Palette.accent)
                            }
                        }
                    }
                } header: {
                    header("Videos")
                } footer: {
                    Text("Nothing downloads on its own here — that is the difference "
                         + "between your phone and a minor's.")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .textCase(nil)
    }
}
