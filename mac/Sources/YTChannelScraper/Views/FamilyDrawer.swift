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
    @State private var newName = ""
    @State private var newIsMinor = true
    @State private var working = false
    @State private var removing: (id: UUID, name: String)?

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
            .alert("Remove \(removing?.name ?? "")?",
                   isPresented: Binding(get: { removing != nil },
                                        set: { if !$0 { removing = nil } })) {
                Button("Remove", role: .destructive) { confirmRemove() }
                Button("Cancel", role: .cancel) { removing = nil }
            } message: {
                Text("They stop appearing for everyone. Nothing is destroyed — a child's "
                     + "shelf stays in the folder, and past approvals keep the name they "
                     + "were signed with. Adding the same name later makes a new person.")
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

            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: $newIsMinor) {
                    Text("Child").tag(true)
                    Text("Parent").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 6) {
                    TextField(newIsMinor ? "Add a child…" : "Add a parent…", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addPerson)
                    Button("Add", action: addPerson)
                        .controlSize(.small)
                        .disabled(working || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            note(newIsMinor
                 ? "A child appears on both parents' devices as soon as iCloud catches up. "
                    + "Set their phone up as them under Minor Mode."
                 : "Adding a parent creates the identity their approvals will be signed "
                    + "with. On their own device they pick their name here to claim it — "
                    + "an app cannot make another person's device become them.")
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

            // Only offered for an adult nobody is using yet, and never for the person
            // this device already is — claiming your own identity twice is not a thing.
            if !isChild, id != profiles.guardian?.id, shelf.isUnclaimed(id) {
                Button("This is me") { claim(id: id, name: name) }
                    .controlSize(.small)
                    .help("Sign this machine's approvals as \(name)")
            } else if let trailing {
                Text(trailing)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        // A context menu rather than a visible ✕: removing somebody is rare and
        // irreversible-ish, and a delete button on every row invites the mis-click.
        .contextMenu {
            if id != profiles.guardian?.id {
                Button("Remove \(name)…", role: .destructive) {
                    removing = (id, name)
                }
            }
        }
    }

    /// Take on an identity somebody else created, rather than minting a second one with
    /// the same name — which would file this person's approvals under a different author.
    private func claim(id: UUID, name: String) {
        let identity = Profiles.Guardian(id: id, name: name)
        guard profiles.adopt(identity) else { return }
        self.name = name
        Task {
            await shelf.markClaimed(id, as: identity)
            await model.syncShelf()
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

    private func confirmRemove() {
        guard let target = removing, let guardian = profiles.guardian else { return }
        removing = nil
        Task { await shelf.removePerson(target.id, as: guardian) }
    }

    private func addPerson() {
        guard let guardian = profiles.guardian else { return }
        let wanted = newName
        let isMinor = newIsMinor
        newName = ""
        working = true
        Task {
            _ = await shelf.createPerson(named: wanted, isMinor: isMinor, as: guardian)
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
