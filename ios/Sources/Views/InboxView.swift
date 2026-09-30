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
                    PullableEmpty(refresh: pull) {
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
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !isMinor, model.inboxCount > 0 {
                        Menu {
                            Button("Save All", systemImage: "bookmark") {
                                withAnimation(.easeOut(duration: 0.2)) { model.claimSent() }
                            }
                            Button("Mark All as Read", systemImage: "envelope.open") {
                                model.markAllRead()
                            }
                            .disabled(model.unreadCount == 0)
                            Divider()
                            Button("Clear Inbox", systemImage: "xmark.bin", role: .destructive) {
                                confirmingClear = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                }
            }
            .confirmationDialog("Clear the inbox?", isPresented: $confirmingClear,
                                titleVisibility: .visible) {
                Button("Clear \(model.inboxCount) Items", role: .destructive) {
                    withAnimation(.easeOut(duration: 0.2)) { model.clearInbox() }
                }
            } message: {
                Text("Nothing is saved. It only leaves this phone's inbox — the sender "
                     + "still sent it, and nobody else's shelf changes.")
            }
            .task { await model.syncShelf() }
        }
    }

    @State private var confirmingClear = false

    /// One pull, held open until the folder has actually settled.
    ///
    /// A send arrives as a file in a shared folder, and nothing pushes a notification when
    /// one lands — the app finds out by looking. Foregrounding looks, which covers most of
    /// it, but not the case this is for: both devices open, one sending and the other
    /// waiting for it.
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
            PullableEmpty(refresh: pull) {
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
            .refreshable { await pull() }
        }
    }

    // MARK: - An admin's phone

    private var adminList: some View {
        List {
            if !waiting.channels.isEmpty {
                Section {
                    ForEach(waiting.channels) { channel in
                        let isRead = model.isRead(channel)
                        HStack(spacing: 8) {
                            UnreadDot(isRead: isRead)
                            ChannelRow(channel: channel)
                            InboxActions(model: model, channel: channel)
                        }
                        .listRowBackground(Color.card)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            ReadToggle(isRead: isRead) { model.setRead(channel, !isRead) }
                        }
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
                        let isRead = model.isRead(video)
                        HStack(spacing: 8) {
                            UnreadDot(isRead: isRead)
                            // Not a Button around the whole row. The actions live inside
                            // it, and an enclosing Button eats their taps — the same thing
                            // that made the Mac's drawer rows undraggable.
                            VideoRow(video: video, showChannel: true)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Watching it is reading it.
                                    model.setRead(video, true)
                                    model.play(video)
                                }

                            InboxActions(model: model, video: video)
                        }
                        .listRowBackground(Color.card)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            ReadToggle(isRead: isRead) { model.setRead(video, !isRead) }
                        }
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
        .refreshable { await pull() }
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

    private var isRead: Bool {
        if let video { return model.isRead(video) }
        if let channel { return model.isRead(channel) }
        return false
    }

    private func setRead(_ value: Bool) {
        if let video { model.setRead(video, value) }
        if let channel { model.setRead(channel, value) }
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
                        ThemedCapsule().fill(isKept ? .clear : Palette.accent.opacity(0.16))
                    }
                    .overlay {
                        ThemedCapsule().strokeBorder(
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
                if isRead {
                    Button("Mark as Unread", systemImage: "envelope.badge") { setRead(false) }
                } else {
                    Button("Mark as Read", systemImage: "envelope.open") { setRead(true) }
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

/// The mark on a row that has not been read, as in Mail. A read row keeps the space so
/// the list does not shift sideways when something is marked.
private struct UnreadDot: View {
    let isRead: Bool

    var body: some View {
        Circle()
            .fill(Palette.accent)
            .frame(width: 8, height: 8)
            .opacity(isRead ? 0 : 1)
            .accessibilityLabel(isRead ? "" : "Unread")
            .accessibilityHidden(isRead)
    }
}

/// The leading swipe: flip read and unread.
private struct ReadToggle: View {
    let isRead: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isRead ? "Unread" : "Read",
                  systemImage: isRead ? "envelope.badge" : "envelope.open")
        }
        .tint(Palette.accent)
    }
}

/// An empty state you can still pull on.
///
/// An empty inbox is the one you most want to refresh — an empty list is what you are
/// trying to change — and `refreshable` needs something scrollable to hang the gesture
/// on, which a centred VStack is not.
///
/// It is a `List` of one full-height row rather than a `ScrollView`, which looks like the
/// long way round. A List gets UIKit's own refresh control on a table view that bounces
/// whether or not its content overflows; a ScrollView has to be talked into bouncing
/// before the gesture exists at all, and inside a GeometryReader that is one more thing
/// that has to go right. This screen has a List on every other path anyway, so the empty
/// one behaving identically is the point rather than a coincidence.
private struct PullableEmpty<Content: View>: View {
    let refresh: () async -> Void
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            List {
                content
                    .frame(maxWidth: .infinity)
                    // One less than the viewport, so the row cannot round up into a
                    // scroll of a couple of points and take the bounce with it.
                    .frame(height: max(0, proxy.size.height - 1))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await refresh() }
        }
    }
}
