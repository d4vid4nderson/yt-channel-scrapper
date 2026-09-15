import SwiftUI

/// Who you can send things to, under the search on the landing screen.
///
/// The thing that makes this a command center rather than a downloader: before you have
/// typed anything, the app says who is on the other end. Empty states are the useful half
/// — a parent who has not set the family up needs to be told that here, where they are
/// looking, rather than to find a ⋯ menu that cannot do anything.
///
/// It lists **children, not devices**, and says so. The shared folder records decisions
/// per child; nothing in it reports whether a phone is switched on, on WiFi, or has
/// finished downloading. Showing "Jack's iPhone" with a green dot would be inventing a
/// status nothing measures. That arrives when a minor's device starts writing its own
/// file — until then the honest word is the child's name and what they have been sent.
struct FamilyStrip: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.profiles.guardian == nil || model.shelf.folder == nil {
                setup("Set up your family to send videos to a minor", "person.2.badge.plus")
            } else if model.shelf.roster.isEmpty {
                setup("Add a minor to send videos to", "person.badge.plus")
            } else {
                roster
            }
        }
        .padding(.top, 26)
    }

    private func setup(_ title: String, _ icon: String) -> some View {
        Button {
            model.showFamily = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 12.5))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.07), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .pointingHand()
    }

    private var roster: some View {
        VStack(spacing: 10) {
            Text("Send to")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)

            HStack(spacing: 10) {
                ForEach(model.shelf.roster, id: \.id) { minor in
                    card(for: minor)
                }
            }
        }
    }

    /// Opens the family sheet rather than a shelf screen, because there is no shelf
    /// screen yet. Better an honest route to the one place these can be managed than a
    /// card that looks tappable and is not.
    private func card(for minor: Profiles.Minor) -> some View {
        Button {
            model.showFamily = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Palette.accent.opacity(0.9))

                // One glyph per device that has announced itself as theirs. Nothing is
                // drawn for a child with no device, which is the truthful state until
                // their phone has opened the app at least once.
                ForEach(model.shelf.devices.filter { $0.personID == minor.id }) { device in
                    Image(systemName: device.kind.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .help("\(device.name) — last seen \(device.lastSeen.formatted(date: .abbreviated, time: .shortened))")
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(minor.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(countText(for: minor))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .fixedSize()
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help("Manage family — send to \(minor.name) with the ⋯ on any video")
    }

    /// What this child has, and on what. The device line is the honest one — it only
    /// names devices that are running the app and have said so.
    private func countText(for minor: Profiles.Minor) -> String {
        let count = model.shelf.approved(for: minor.id).count
        let items = count == 0 ? "nothing yet" : "\(count) item\(count == 1 ? "" : "s")"
        let theirs = model.shelf.devices.filter { $0.personID == minor.id }
        guard !theirs.isEmpty else { return items + " · no device yet" }
        return items + " · " + theirs.map(\.kind.noun).joined(separator: ", ")
    }
}
