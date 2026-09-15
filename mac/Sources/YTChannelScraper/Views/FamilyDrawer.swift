import AppKit
import SwiftUI

/// Who you are curating for, on the right edge.
///
/// Built from the app's own vocabulary rather than AppKit's: capsule fields on a faint
/// white wash, text buttons that only colour on hover, chips for roles. The stock
/// `.roundedBorder` field and the default push button are grey, heavy, and belong to a
/// different application — next to the search pill and the drawer chips they read as
/// something bolted on.
///
/// Words are rationed too. The first draft explained every rule in a paragraph under each
/// control; a panel you open twenty times a day should not re-teach itself every time. The
/// long explanations moved into `help` tooltips, which is where a detail you need once
/// belongs.
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
                    count: shelf.roster.count + shelf.guardians.count,
                    close: { model.showFamilyDrawer = false }
                )
                Divider().overlay(.white.opacity(0.09))

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        you
                        folder
                        if profiles.guardian != nil, shelf.folder != nil { people }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
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
                Text("They stop appearing for everyone. Nothing is destroyed — a minor's "
                     + "shelf stays in the folder, and past approvals keep the name they "
                     + "were signed with.")
            }
        }
    }

    // MARK: - You

    private var you: some View {
        section("You") {
            CapsuleField(text: $name, prompt: "Your name", onSubmit: saveName)
                .help("Shown against what you approve, so other admins can see who decided what")
            if nameChanged {
                QuietButton(title: "Save", accent: true, action: saveName)
            }
        }
    }

    private var nameChanged: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != (profiles.guardian?.name ?? "")
    }

    private func saveName() {
        guard nameChanged else { return }
        _ = profiles.setGuardianName(name.trimmingCharacters(in: .whitespaces))
        Task { await model.syncShelf() }
    }

    // MARK: - Folder

    private var folder: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Shared folder")
            HStack(spacing: 8) {
                Image(systemName: shelf.folder == nil ? "folder.badge.plus" : "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Text(folderLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(shelf.folder == nil ? 0.35 : 0.8))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 6)
                QuietButton(title: shelf.folder == nil ? "Choose" : "Change",
                            action: pickFolder)
            }
            .help(shelf.folder?.path
                  ?? "Make a folder in iCloud Drive, share it with the other admin in Finder, then point each device at it")

            if pickedTheRoot {
                Label("This is all of iCloud Drive. Pick a folder inside it — you cannot "
                      + "share the whole drive with the other parent.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.accent.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let read = shelf.lastRead, shelf.folder != nil {
                Text("Last read \(read.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    /// What Finder would call it.
    ///
    /// On disk, iCloud Drive is `~/Library/Mobile Documents/com~apple~CloudDocs`, so the
    /// raw components are a tour of implementation detail. Anchoring on that container
    /// and showing only what is *inside* it is the only version that matches what somebody
    /// picked in the panel.
    private var folderLabel: String {
        guard let url = shelf.folder else { return "Not chosen yet" }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let root = parts.firstIndex(of: "com~apple~CloudDocs") else {
            return parts.suffix(2).joined(separator: " / ")
        }
        let inside = parts[parts.index(after: root)...]
        return inside.isEmpty ? "iCloud Drive" : "iCloud Drive / " + inside.joined(separator: " / ")
    }

    /// Whether they picked iCloud Drive itself rather than a folder in it. Worth saying:
    /// the app will write its files among everything else they keep there, and a folder
    /// shared with the other parent has to be a folder, not the whole drive.
    private var pickedTheRoot: Bool {
        guard let url = shelf.folder else { return false }
        return url.pathComponents.last == "com~apple~CloudDocs"
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
        VStack(alignment: .leading, spacing: 10) {
            heading("Manage family")

            ForEach(shelf.guardians, id: \.id) { guardian in
                PersonRow(
                    name: guardian.name,
                    isMinor: false,
                    isYou: guardian.id == profiles.guardian?.id,
                    unclaimed: shelf.isUnclaimed(guardian.id),
                    devices: shelf.devices.filter { $0.personID == guardian.id },
                    count: nil,
                    setRole: { setRole(guardian.id, isMinor: $0) },
                    claim: { claim(id: guardian.id, name: guardian.name) },
                    remove: { removing = (guardian.id, guardian.name) }
                )
            }

            ForEach(shelf.roster, id: \.id) { minor in
                PersonRow(
                    name: minor.name,
                    isMinor: true,
                    isYou: false,
                    unclaimed: false,
                    devices: shelf.devices.filter { $0.personID == minor.id },
                    count: shelf.approved(for: minor.id).count,
                    setRole: { setRole(minor.id, isMinor: $0) },
                    claim: nil,
                    remove: { removing = (minor.id, minor.name) }
                )
            }

            addRow
        }
    }

    /// Adding is one line: a role, a name, a button that only exists once there is
    /// something to add.
    private var addRow: some View {
        // Two lines, not one. Sharing a row with the toggle left the name field about
        // eight characters wide in a 330pt drawer — the field is the part being typed
        // into and should get the width.
        VStack(alignment: .leading, spacing: 7) {
            RoleToggle(isMinor: $newIsMinor)
            HStack(spacing: 8) {
                CapsuleField(text: $newName,
                             prompt: newIsMinor ? "Minor's name" : "Admin's name",
                             onSubmit: addPerson)
                if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    QuietButton(title: "Add", accent: true, action: addPerson)
                        .disabled(working)
                }
            }
        }
        .padding(.top, 6)
        .help(newIsMinor
              ? "A minor appears on every admin's device as soon as iCloud catches up"
              : "Creates the identity their approvals are signed with — on their own device they claim it")
    }

    // MARK: - Actions

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

    private func setRole(_ id: UUID, isMinor: Bool) {
        guard let guardian = profiles.guardian else { return }
        Task { await shelf.setRole(id, isMinor: isMinor, as: guardian) }
    }

    private func claim(id: UUID, name: String) {
        let identity = Profiles.Guardian(id: id, name: name)
        guard profiles.adopt(identity) else { return }
        self.name = name
        Task {
            await shelf.markClaimed(id, as: identity)
            await model.syncShelf()
        }
    }

    private func confirmRemove() {
        guard let target = removing, let guardian = profiles.guardian else { return }
        removing = nil
        Task { await shelf.removePerson(target.id, as: guardian) }
    }

    // MARK: - Furniture

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.35))
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(title)
            HStack(spacing: 8) { content() }
        }
    }
}

// MARK: - Parts

/// A text field that looks like the rest of the app: no bezel, a faint wash, a hairline.
/// `DrawerFilterField` does the same thing for the filter; this is the plain version.
private struct CapsuleField: View {
    @Binding var text: String
    let prompt: String
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(prompt)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(.white.opacity(focused ? 0.10 : 0.06), in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                focused ? Palette.accent.opacity(0.45) : .white.opacity(0.09),
                lineWidth: 1
            )
        }
        .animation(.easeOut(duration: 0.14), value: focused)
    }
}

/// A text button that is quiet at rest and lights on hover — the same manner as the
/// drawer footers, rather than AppKit's grey slab.
private struct QuietButton: View {
    let title: String
    var accent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(accent ? Palette.accent : .white.opacity(hovering ? 0.9 : 0.55))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(.white.opacity(hovering ? 0.10 : 0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHand()
    }
}

/// Two chips, not a segmented control. The stock one is a grey slab the width of its
/// container; this is the size of its two words.
private struct RoleToggle: View {
    @Binding var isMinor: Bool

    var body: some View {
        HStack(spacing: 2) {
            chip("Minor", on: isMinor) { isMinor = true }
            chip("Admin", on: !isMinor) { isMinor = false }
        }
        .padding(2)
        .background(.white.opacity(0.06), in: Capsule())
    }

    private func chip(_ title: String, on: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(on ? .white : .white.opacity(0.45))
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(on ? AnyShapeStyle(Palette.accent.opacity(0.75))
                               : AnyShapeStyle(Color.clear),
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .pointingHand()
    }
}

/// One person: who they are, what they hold it on, and how much they have.
private struct PersonRow: View {
    let name: String
    let isMinor: Bool
    let isYou: Bool
    let unclaimed: Bool
    let devices: [DeviceRecord]
    let count: Int?
    let setRole: (Bool) -> Void
    let claim: (() -> Void)?
    let remove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Palette.accent.opacity(isMinor ? 0.22 : 0.32))
                .frame(width: 26, height: 26)
                .overlay {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    // The role is the control. Changing somebody from child to parent is
                    // rare enough not to deserve a row of its own, and obvious enough
                    // here that nobody has to look for it.
                    Menu {
                        Button("Minor") { setRole(true) }
                        Button("Admin") { setRole(false) }
                    } label: {
                        HStack(spacing: 2) {
                            Text(isYou ? "you" : (isMinor ? "minor" : "admin"))
                            // Only once the row is under the cursor: at rest this is a
                            // label, and a permanent chevron on every row is noise.
                            if hovering && !isYou {
                                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                            }
                        }
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(hovering && !isYou ? 0.7 : 0.45))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(isYou)

                    ForEach(devices) { device in
                        Image(systemName: device.kind.icon)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.4))
                            .help(help(for: device))
                    }
                    if devices.isEmpty && !isYou {
                        Text("no device yet")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }

            Spacer(minLength: 4)

            if unclaimed, let claim {
                QuietButton(title: "This is me", action: claim)
            } else if let count {
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Only on hover, and never for yourself.
            if hovering && !isYou {
                Button(action: remove) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help("Remove \(name)")
                .pointingHand()
                .transition(.opacity)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func help(for device: DeviceRecord) -> String {
        var parts = ["\(device.name) — last seen "
                     + device.lastSeen.formatted(date: .abbreviated, time: .shortened)]
        if device.isMinor {
            parts.append("\(device.downloaded) of \(device.approved) downloaded")
        }
        return parts.joined(separator: ", ")
    }
}
