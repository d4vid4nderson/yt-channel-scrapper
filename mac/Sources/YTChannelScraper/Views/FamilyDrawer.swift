import AppKit
import SwiftUI

/// Who you are curating for, on the right edge.
///
/// This took the edge that used to hold saved videos, which moved in beside the channels
/// — both were lists of things kept, and neither needed a screen edge of its own. What
/// belongs on a permanent edge in a command center is the other end: the people, their
/// devices, and how far behind each one is.
///
/// A panel rather than the sheet it started as. Setup is a one-off, but the list is not:
/// it is how you check that a child's phone has actually picked up what you sent, which
/// is a thing you glance at while doing something else.
struct FamilyDrawer: View {
    @Bindable var model: AppModel

    @State private var name = ""
    @State private var childName = ""
    @State private var working = false

    private var profiles: Profiles { model.profiles }
    private var shelf: ShelfStore { model.shelf }

    var body: some View {
        SideDrawer(side: .trailing, isPresented: $model.showFamilyDrawer) {
            VStack(spacing: 0) {
                DrawerHead(
                    title: "Family",
                    count: shelf.roster.count,
                    close: { model.showFamilyDrawer = false }
                )
                Divider().overlay(.white.opacity(0.09))

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        you
                        folder
                        if profiles.guardian != nil, shelf.folder != nil { people }
                    }
                    .padding(14)
                }
                .scrollIndicators(.visible)

                if let problem = shelf.problem {
                    Divider().overlay(.white.opacity(0.09))
                    DrawerNote(text: problem) {}
                }
            }
            .task {
                name = profiles.guardian?.name ?? ""
                await model.syncShelf()
            }
        }
    }

    // MARK: - You

    private var you: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("You")
            HStack(spacing: 6) {
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveName)
                Button("Save", action: saveName)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || name.trimmingCharacters(in: .whitespaces) == (profiles.guardian?.name ?? ""))
            }
            note("Shown against what you approve, so the other parent can see who decided what.")
        }
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = profiles.setGuardianName(trimmed)
        Task { await model.syncShelf() }
    }

    // MARK: - Folder

    private var folder: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Shared folder")
            HStack(spacing: 6) {
                Text(folderLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(shelf.folder == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(shelf.folder?.path ?? "")
                Spacer(minLength: 4)
                Button(shelf.folder == nil ? "Choose…" : "Change…", action: pickFolder)
                    .controlSize(.small)
            }
            if shelf.folder == nil {
                note("Make a folder in iCloud Drive, share it with the other parent in "
                     + "Finder, then point each device at it. No app can create or share "
                     + "that folder for you.")
            } else if let read = shelf.lastRead {
                note("Last read \(read.formatted(date: .omitted, time: .shortened)).")
            }
        }
    }

    /// iCloud Drive's root is literally named "com~apple~CloudDocs", which tells nobody
    /// anything and hides whether the root or a folder inside it was picked.
    private var folderLabel: String {
        guard let url = shelf.folder else { return "Not chosen" }
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.map { $0 == "com~apple~CloudDocs" ? "iCloud Drive" : $0 }
            .suffix(2).joined(separator: " / ")
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if shelf.adopt(url) { Task { await model.syncShelf() } }
    }

    // MARK: - People

    private var people: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("People")

            ForEach(shelf.guardians, id: \.id) { guardian in
                row(name: guardian.name,
                    role: guardian.id == profiles.guardian?.id ? "you" : "parent",
                    isChild: false,
                    id: guardian.id,
                    trailing: nil)
            }

            ForEach(shelf.roster, id: \.id) { minor in
                row(name: minor.name,
                    role: "child",
                    isChild: true,
                    id: minor.id,
                    trailing: "\(shelf.approved(for: minor.id).count)")
            }

            HStack(spacing: 6) {
                TextField("Add a child…", text: $childName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addChild)
                Button("Add", action: addChild)
                    .controlSize(.small)
                    .disabled(working || childName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            note("Another parent appears once they name themselves and pick this same "
                 + "folder — nothing to invite or accept. Device icons show only devices "
                 + "running this app: there is no way to read the devices on an Apple ID.")
        }
    }

    private func row(name: String, role: String, isChild: Bool, id: UUID,
                     trailing: String?) -> some View {
        let theirs = shelf.devices.filter { $0.personID == id }
        return HStack(spacing: 7) {
            Image(systemName: isChild ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
            Text(name).font(.system(size: 12.5)).lineLimit(1)
            Text(role)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(.white.opacity(0.08), in: Capsule())

            ForEach(theirs) { device in
                Image(systemName: device.kind.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .help(deviceHelp(device))
            }

            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The gap between approved and downloaded is the number worth surfacing — it is the
    /// download that has not finished yet.
    private func deviceHelp(_ device: DeviceRecord) -> String {
        var parts = ["\(device.name) — last seen "
                     + device.lastSeen.formatted(date: .abbreviated, time: .shortened)]
        if device.isMinor {
            parts.append("\(device.downloaded) of \(device.approved) downloaded")
        }
        return parts.joined(separator: ", ")
    }

    private func addChild() {
        guard let guardian = profiles.guardian else { return }
        let wanted = childName
        childName = ""
        working = true
        Task {
            _ = await shelf.createMinor(named: wanted, as: guardian)
            working = false
        }
    }

    // MARK: - Furniture

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.35))
            .fixedSize(horizontal: false, vertical: true)
    }
}
