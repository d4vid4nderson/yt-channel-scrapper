import SwiftUI

/// The ⋯ on a row: keep it, fetch it, or put it on a child's shelf.
///
/// One menu for videos and channels because the decisions are the same shape, and one
/// place for them because there are now three verbs and a row cannot carry three buttons
/// without becoming a toolbar.
///
/// Approving writes a full `ShelfEntry` rather than calling `ShelfStore.set`, which takes
/// only a kind and an id. The difference matters: an entry carries its own title and, for
/// a video, its channel. The child's device draws its shelf and names its downloads from
/// those fields alone — it makes no listing calls to YouTube at all — and the channel is
/// what lets a later veto of that channel take this video with it.
struct ShelfMenu: View {
    @Bindable var model: AppModel

    /// Exactly one of these. A channel row passes a channel, a video row a video.
    var video: Video?
    var channel: Channel?

    var body: some View {
        Menu {
            keeping
            if video != nil, !model.isMinor {
                Divider()
                Button("Download", systemImage: "arrow.down.circle") {
                    if let video { model.download([video]) }
                }
            }
            if !model.isMinor {
                Divider()
                sending
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
                // A full-height target rather than a 32pt square: this sits inches from
                // a navigation chevron, and the cost of a near miss is opening a channel
                // you meant to send.
                .frame(width: 40, height: Metrics.tap)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Keeping

    @ViewBuilder
    private var keeping: some View {
        if let video {
            Button(model.isSaved(video) ? "Remove from Saved" : "Save",
                   systemImage: model.isSaved(video) ? "bookmark.slash" : "bookmark") {
                model.toggleSaved(video)
            }
        } else if let channel {
            Button(model.library.contains(channel.id) ? "Remove from Saved" : "Save",
                   systemImage: model.library.contains(channel.id) ? "bookmark.slash" : "bookmark") {
                model.library.toggle(channel)
            }
        }
    }

    // MARK: - Sending

    /// One submenu per child, so the verb reads as "send this to Jack" rather than
    /// "approve" — which is the same operation described from the app's side instead of
    /// the parent's.
    @ViewBuilder
    private var sending: some View {
        if model.profiles.guardian == nil || model.shelf.folder == nil {
            Button("Set up Family first…", systemImage: "person.2") {
                model.wantsFamilySetup = true
            }
        } else if model.shelf.roster.isEmpty {
            Button("Add a child first…", systemImage: "person.badge.plus") {
                model.wantsFamilySetup = true
            }
        } else {
            ForEach(model.shelf.roster, id: \.id) { minor in
                let on = isOn(minor)
                Button(
                    on ? "Take off \(minor.name)'s shelf" : "Send to \(minor.name)",
                    systemImage: on ? "minus.circle" : "paperplane"
                ) {
                    send(to: minor, approve: !on)
                }
            }
        }
    }

    private func isOn(_ minor: Profiles.Minor) -> Bool {
        guard let key else { return false }
        return model.shelf.approved(for: minor.id).contains(key)
    }

    private var key: ShelfEntry.Key? {
        if let video { return ShelfEntry.Key(kind: .video, id: video.id) }
        if let channel { return ShelfEntry.Key(kind: .channel, id: channel.id) }
        return nil
    }

    private func send(to minor: Profiles.Minor, approve: Bool) {
        guard let guardian = model.profiles.guardian else { return }
        let entry: ShelfEntry
        if let video {
            entry = ShelfEntry(
                kind: .video,
                id: video.id,
                state: approve ? .approved : .removed,
                guardian: guardian.name,
                title: video.title,
                // The channel travels with the video so that blocking the channel later
                // withdraws this too. Without it the veto would not reach what is
                // already on the phone.
                channelID: video.channelId
            )
        } else if let channel {
            entry = ShelfEntry(
                kind: .channel,
                id: channel.id,
                state: approve ? .approved : .removed,
                guardian: guardian.name,
                title: channel.title
            )
        } else {
            return
        }

        Task {
            let ok = await model.shelf.record([entry], for: minor, as: guardian)
            model.banner = ok
                ? (approve
                    ? "Sent to \(minor.name)."
                    : "Taken off \(minor.name)'s shelf.")
                : (model.shelf.problem ?? "That could not be saved to the shared folder.")
        }
    }
}
