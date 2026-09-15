import SwiftUI

/// The ⋯ on a row: send this to a child, or take it back off their shelf.
///
/// The Mac's counterpart to the iPhone's menu of the same name, and deliberately smaller:
/// a Mac row already carries a save mark, a download button and a preview, so the only
/// thing missing was the shelf. Adding save and download here too would be three ways to
/// do the same two things.
///
/// Reads "Send to Jack" rather than "Approve" — the same write, described as the parent's
/// action rather than the app's.
struct ShelfMenu: View {
    @Bindable var model: AppModel

    /// Exactly one of these.
    var video: Video?
    var channel: Channel?

    var body: some View {
        Menu {
            if model.profiles.guardian == nil || model.shelf.folder == nil {
                Button("Set up Family…") { model.showFamily = true }
            } else if model.shelf.roster.isEmpty {
                Button("Add a child…") { model.showFamily = true }
            } else {
                ForEach(model.shelf.roster, id: \.id) { minor in
                    let on = isOn(minor)
                    Button(on ? "Take off \(minor.name)'s shelf" : "Send to \(minor.name)") {
                        send(to: minor, approve: !on)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .help("Send this to one of your children")
        .pointingHand()
    }

    private func isOn(_ minor: Profiles.Minor) -> Bool {
        if let video { return model.isOnShelf(kind: .video, id: video.id, for: minor) }
        if let channel { return model.isOnShelf(kind: .channel, id: channel.id, for: minor) }
        return false
    }

    private func send(to minor: Profiles.Minor, approve: Bool) {
        Task {
            if let video {
                await model.send(video, to: minor, approve: approve)
            } else if let channel {
                await model.send(channel, to: minor, approve: approve)
            }
        }
    }
}
