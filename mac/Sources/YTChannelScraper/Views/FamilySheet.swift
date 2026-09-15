import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Who you are, where the shared folder is, and who you are curating for — the Mac's
/// copy of the iPhone's Family screen.
///
/// A sheet rather than a drawer: this is setup, done once and then rarely, and the three
/// drawers are for things you return to. It uses `NSOpenPanel` directly because a Mac
/// folder picker is one line here and a `fileImporter` ceremony there.
struct FamilySheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var childName = ""
    @State private var working = false

    private var profiles: Profiles { model.profiles }
    private var shelf: ShelfStore { model.shelf }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Family")
                .font(.system(size: 18, weight: .semibold))

            you
            Divider()
            folder
            if profiles.guardian != nil, shelf.folder != nil {
                Divider()
                children
            }

            HStack {
                if let problem = shelf.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.accent)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .task {
            name = profiles.guardian?.name ?? ""
            await model.syncShelf()
        }
    }

    // MARK: - You

    private var you: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveName)
                Button("Save", action: saveName)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || name.trimmingCharacters(in: .whitespaces) == (profiles.guardian?.name ?? ""))
            }
            Text("Shown against the videos you approve, so the other parent can see who "
                 + "decided what.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = profiles.setGuardianName(trimmed)
    }

    // MARK: - Folder

    private var folder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shared folder")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                // Not `lastPathComponent`: iCloud Drive's root is literally named
                // "com~apple~CloudDocs", which tells a parent nothing and hides the fact
                // that they may have picked the root rather than a folder inside it.
                Text(folderLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(shelf.folder == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(shelf.folder?.path ?? "")
                Spacer()
                Button(shelf.folder == nil ? "Choose…" : "Change…", action: pickFolder)
                if shelf.folder != nil {
                    Button("Forget") { shelf.forgetFolder() }
                }
            }
            Text("Make a folder in iCloud Drive, share it with the other parent in Finder, "
                 + "then point each device at it. Nothing can automate that part — there "
                 + "is no API to create or share an iCloud Drive folder.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The last two components, with iCloud Drive's container name translated back into
    /// what Finder calls it.
    private var folderLabel: String {
        guard let url = shelf.folder else { return "Not chosen" }
        let parts = url.pathComponents.filter { $0 != "/" }
        let readable = parts.map { $0 == "com~apple~CloudDocs" ? "iCloud Drive" : $0 }
        return readable.suffix(2).joined(separator: " / ")
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if shelf.adopt(url) {
            Task { await model.syncShelf() }
        }
    }

    // MARK: - Children

    private var children: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("People")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)

            // Adults are listed, not added. A guardian's identity is made on their own
            // device when they name themselves — there is no way to create it for them —
            // so they appear here as soon as they have picked this folder, and the note
            // below says so instead of offering a button that cannot work.
            ForEach(shelf.guardians, id: \.id) { guardian in
                person(name: guardian.name,
                       role: guardian.id == profiles.guardian?.id ? "you" : "parent",
                       detail: nil,
                       id: guardian.id)
            }

            ForEach(shelf.roster, id: \.id) { minor in
                person(name: minor.name,
                       role: "child",
                       detail: "\(shelf.approved(for: minor.id).count) approved",
                       id: minor.id)
            }

            HStack {
                TextField("Add a child…", text: $childName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addChild)
                Button("Add", action: addChild)
                    .disabled(working || childName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("Another parent appears here once they open the app, name themselves and "
                 + "pick this same folder. There is nothing to invite or accept — and no "
                 + "way to create their identity from this machine.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One person, with whatever devices have announced themselves as theirs.
    ///
    /// Only devices running this app can ever be listed: Apple publishes no way to read
    /// the devices on an Apple ID. A person with none shows nothing rather than a
    /// placeholder, because "no device yet" is a real and temporary state.
    private func person(name: String, role: String, detail: String?, id: UUID) -> some View {
        let theirs = shelf.devices.filter { $0.personID == id }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: role == "child" ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                .foregroundStyle(Palette.accent)
            Text(name)
            Text(role)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.white.opacity(0.08), in: Capsule())

            ForEach(theirs) { device in
                Label(device.name, systemImage: device.kind.icon)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .help("\(device.name) — last seen \(device.lastSeen.formatted(date: .abbreviated, time: .shortened))"
                          + (device.isMinor ? ", \(device.downloaded) of \(device.approved) downloaded" : ""))
            }

            Spacer()
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
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
}
