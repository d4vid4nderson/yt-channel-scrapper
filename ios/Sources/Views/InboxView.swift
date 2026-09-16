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
                    PullableEmpty {
                        Placeholder(
                            icon: "tray",
                            title: "Nothing new",
                            detail: "When another admin sends you a channel or a video it "
                                + "waits here until you deal with it. Nothing downloads by "
                                + "itself. Pull down to check for anything just sent."
                        )
                    }
                } else {
                    adminList
                }
            }
            .ground()
            // A send arrives as a file in a shared folder, and nothing pushes a
            // notification when one lands — the app finds out by looking. Foregrounding
            // looks, which covers most of it, but not the case this is for: both devices
            // already open, one sending and the other waiting for it.
            .refreshable { await pull() }
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

    /// One pull, held open until the folder has actually settled.
    ///
    /// A read that met a file iCloud had not finished handing over comes back successful
    /// having seen less than the folder holds, and the store books another go. Ending the
    /// spinner there would show you the same empty list you pulled to change — and this
    /// is pulled exactly when something has just been sent, which is exactly when a file
    /// is mid-download. So it waits for the retries, with a ceiling: past a second or two
    /// the honest thing is to stop spinning and let you pull again.
    private func pull() async {
        await model.syncShelf()
        var waits = 0
        while model.shelf.pendingRetry, waits < 6 {
            try? await Task.sleep(for: .milliseconds(350))
            waits += 1
        }
    }

    // MARK: - A minor's phone

    /// Read-only, and says so. There is nothing to accept: it is already on their
    /// shelves and the approved videos are already downloading.
    @ViewBuilder
    private var minorList: some View {
        if everything.channels.isEmpty && everything.videos.isEmpty {
            PullableEmpty {
                Placeholder(
                    icon: "tray",
                    title: "Nothing yet",
                    detail: "Channels and videos a grown-up sends you will show up here, "
                        + "and on your Home shelves. Pull down to check."
                )
            }
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
                        HStack(spacing: 8) {
                            ChannelRow(channel: channel)
                            InboxActions(model: model, channel: channel)
                        }
                        .listRowBackground(Color.card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.dismiss(channel: channel)
                            } label: { Label("Remove", systemImage: "xmark") }
                        }
                    }
                } header: {
                    header("Channels")
                } footer: {
                    Text("Saving puts a channel on your Home shelf and clears it from "
                         + "here. Either way nothing changes for anybody else — the "
                         + "sender still sent it.")
                }
            }

            if !waiting.videos.isEmpty {
                Section {
                    ForEach(waiting.videos) { video in
                        HStack(spacing: 8) {
                            // Not a Button around the whole row. The actions live inside
                            // it, and an enclosing Button eats their taps — the same thing
                            // that made the Mac's drawer rows undraggable.
                            VideoRow(video: video, showChannel: true)
                                .contentShape(Rectangle())
                                .onTapGesture { model.play(video) }

                            InboxActions(model: model, video: video)
                        }
                        .listRowBackground(Color.card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.dismiss(video: video)
                            } label: { Label("Remove", systemImage: "xmark") }
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

/// Keep this, on the row it arrived on.
///
/// The inbox used to hide every verb behind a swipe, which meant the only thing you could
/// do to something somebody sent you was open it — and opening a channel to save it goes
/// off to YouTube for a listing nobody asked for. A send is a suggestion, so accepting one
/// is the whole job of this screen and deserves to be visible.
///
/// Save is the button; everything else is behind the ⋯ the rest of the app already uses.
/// Three buttons on a row makes a toolbar, which is the same reason `ShelfMenu` exists.
private struct InboxActions: View {
    @Bindable var model: AppModel

    /// Exactly one of these, as in `ShelfMenu`.
    var video: Video?
    var channel: Channel?

    private var isKept: Bool {
        if let video { return model.isKept(video) }
        if let channel { return model.isKept(channel) }
        return false
    }

    /// Saving also clears the row. Animated because the row is what you are looking at
    /// when it happens, and something leaving a list without moving reads as a glitch.
    private func save() {
        withAnimation(.easeOut(duration: 0.2)) {
            if let video { model.keep(video: video) }
            if let channel { model.keep(channel: channel) }
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            // The kept state is still drawn, for the one case that survives: something
            // saved from the Home shelf while its inbox row was open.
            Button(action: save) {
                Label(isKept ? "Saved" : "Save",
                      systemImage: isKept ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isKept ? Color.secondaryText : Palette.accent)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background {
                        Capsule().fill(isKept ? .clear : Palette.accent.opacity(0.16))
                    }
                    .overlay {
                        Capsule().strokeBorder(
                            isKept ? Color.secondaryText.opacity(0.22) : .clear)
                    }
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.15), value: isKept)

            Menu {
                if let video {
                    Button("Download", systemImage: "arrow.down.circle") {
                        model.download([video])
                    }
                    Divider()
                }
                Button("Remove from Inbox", systemImage: "xmark", role: .destructive) {
                    if let video { model.dismiss(video: video) }
                    if let channel { model.dismiss(channel: channel) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .frame(width: 32, height: Metrics.tap)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// An empty state you can still pull on.
///
/// An empty inbox is the one you most want to refresh — you are waiting for something —
/// and `refreshable` needs a scroll view to hang the gesture on, which a centred VStack
/// is not. This keeps the layout identical and makes the gesture exist: the placeholder is
/// given the full height of the viewport inside a ScrollView that bounces even when its
/// content fits.
private struct PullableEmpty<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content.frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.always)
        }
    }
}
