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

    /// The household's label. Cosmetic and shared.
    @State private var family = ""
    /// This admin's own display name — what signs approvals. Edited from your own row
    /// under Admins, because that is where it means something.
    @State private var name = ""
    /// Which section the cursor is dragging over, so it can light up.
    @State private var dropTarget: Bool?
    @State private var newName = ""
    /// Which section is accepting a name, if any. Replaces the role toggle: the section
    /// you clicked + on *is* the role, so there is nothing left to choose.
    @State private var addingMinor: Bool?
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
                        you.padding(.horizontal, 10)
                        folder.padding(.horizontal, 10)
                        if profiles.guardian != nil, shelf.folder != nil { people }
                    }
                    .padding(.horizontal, 6)
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
                family = shelf.familyName
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
        section("Family name") {
            CapsuleField(text: $family, prompt: "Anderson", onSubmit: saveFamily)
                .help("What this household is called. A label everybody sees — it is not "
                      + "the name your approvals are signed with.")
            if familyChanged {
                QuietButton(title: "Save", accent: true, action: saveFamily)
            }
        }
    }

    private var familyChanged: Bool {
        family.trimmingCharacters(in: .whitespaces) != shelf.familyName
    }

    private func saveFamily() {
        guard familyChanged, let guardian = profiles.guardian else { return }
        Task { await shelf.setFamilyName(family, as: guardian) }
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

    /// Two groups, not one list.
    ///
    /// Admins and minors are read for different reasons — one is "who else can decide",
    /// the other is "who am I sending to, and have they got it" — and the second grows
    /// while the first stays at two. A single list made you read every row to find out
    /// which kind each person was.
    private var people: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("Admins", isMinor: false,
                  isEmpty: shelf.guardians.isEmpty, empty: "No admins yet.") {
                ForEach(shelf.guardians, id: \.id) { guardian in
                    PersonRow(
                        id: guardian.id,
                        name: guardian.name,
                        isMinor: false,
                        isYou: guardian.id == profiles.guardian?.id,
                        unclaimed: shelf.isUnclaimed(guardian.id),
                        devices: shelf.devices.filter { $0.personID == guardian.id },
                        count: nil,
                        expected: shelf.expectedDevice(for: guardian.id),
                        setExpected: { setExpected(guardian.id, $0) },
                        claim: { claim(id: guardian.id, name: guardian.name) },
                        rename: renameBinding(for: guardian.id),
                        remove: { removing = (guardian.id, guardian.name) }
                    )
                }
            }

            group("Minors", isMinor: true,
                  isEmpty: shelf.roster.isEmpty, empty: "Nobody to send to yet.") {
                ForEach(shelf.roster, id: \.id) { minor in
                    PersonRow(
                        id: minor.id,
                        name: minor.name,
                        isMinor: true,
                        isYou: false,
                        unclaimed: false,
                        devices: shelf.devices.filter { $0.personID == minor.id },
                        count: shelf.approved(for: minor.id).count,
                        expected: shelf.expectedDevice(for: minor.id),
                        setExpected: { setExpected(minor.id, $0) },
                        claim: nil,
                        remove: { removing = (minor.id, minor.name) }
                    )
                }
            }
        }
    }

    /// A headed group with its own add button.
    ///
    /// The button is the role: clicking + on Minors adds a minor. One fewer decision than
    /// a shared field with a toggle, and it puts the new person where you were looking.
    private func group(_ title: String, isMinor: Bool, isEmpty: Bool, empty: String,
                       @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                heading(title)
                Spacer(minLength: 4)
                AddButton(help: isMinor
                          ? "Add a minor — or drag somebody here to make them one"
                          : "Add an admin — or drag somebody here to make them one") {
                    newName = ""
                    addingMinor = (addingMinor == isMinor) ? nil : isMinor
                }
            }

            rows()

            // Not said while a field is open below it — that is already explaining itself.
            if isEmpty && addingMinor != isMinor {
                Text(empty)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.28))
            }

            if addingMinor == isMinor {
                HStack(spacing: 8) {
                    CapsuleField(text: $newName,
                                 prompt: isMinor ? "Minor's name" : "Admin's name",
                                 onSubmit: addPerson)
                    if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                        QuietButton(title: "Add", accent: true, action: addPerson)
                            .disabled(working)
                    }
                }
                .help(isMinor
                      ? "A minor appears on every admin's device as soon as iCloud catches up"
                      : "Creates the identity their approvals are signed with — on their own device they claim it")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Held at rest as well as when lit, so the rows do not jump sideways the moment
        // a drag crosses them. The scroll view's own inset is reduced to match.
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            (dropTarget == isMinor ? Palette.accent.opacity(0.10) : .clear),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(dropTarget == isMinor ? Palette.accent.opacity(0.35) : .clear)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
            // Dropping somebody into the section they are already in is a no-op rather
            // than a write — every write lands in a file the other admin reads.
            let alreadyHere = isMinor
                ? shelf.roster.contains { $0.id == id }
                : shelf.guardians.contains { $0.id == id }
            guard !alreadyHere else { return false }
            setRole(id, isMinor: isMinor)
            return true
        } isTargeted: { targeted in
            dropTarget = targeted ? isMinor : nil
        }
        .animation(.easeOut(duration: 0.14), value: addingMinor)
        .animation(.easeOut(duration: 0.12), value: dropTarget)
    }

    // MARK: - Actions

    private func addPerson() {
        guard let guardian = profiles.guardian, let isMinor = addingMinor else { return }
        let wanted = newName
        newName = ""
        addingMinor = nil
        working = true
        Task {
            _ = await shelf.createPerson(named: wanted, isMinor: isMinor, as: guardian)
            working = false
        }
    }

    /// Your own row, and only yours, gets an editable name.
    private func renameBinding(for id: UUID) -> PersonRow.Rename? {
        guard id == profiles.guardian?.id else { return nil }
        return PersonRow.Rename(text: $name, save: saveName)
    }

    private func setExpected(_ id: UUID, _ kind: DeviceRecord.Kind?) {
        guard let guardian = profiles.guardian else { return }
        Task { await shelf.setExpectedDevice(id, kind: kind, as: guardian) }
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

/// One person: their name, what they carry, and how much is waiting for them.
///
/// Two lines and three columns, aligned on a grid rather than by eye. What was here
/// before put the role beside the name — which the section heading above already says —
/// and let a menu set its own type size, so the second line came out larger than the
/// name's own subtitle and nothing shared a baseline.
private struct PersonRow: View {
    let id: UUID
    let name: String
    let isMinor: Bool
    let isYou: Bool
    let unclaimed: Bool
    let devices: [DeviceRecord]
    let count: Int?
    let expected: DeviceRecord.Kind?
    let setExpected: (DeviceRecord.Kind?) -> Void
    let claim: (() -> Void)?
    /// Only your own row gets one: the field is your display name, edited in place.
    var rename: Rename?
    let remove: () -> Void

    struct Rename {
        let text: Binding<String>
        let save: () -> Void
    }

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            monogram

            VStack(alignment: .leading, spacing: 1) {
                first
                second
            }

            Spacer(minLength: 8)

            // Fixed widths so every row's right edge lines up, whatever is in it.
            if let count {
                Text("\(count)")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(count == 0 ? 0.25 : 0.55))
            }

            removeButton
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .draggable(id.uuidString) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.7), in: Capsule())
        }
        .onHover { hovering = $0 }
        // Claiming an identity somebody else created happens once, on one machine, ever.
        // A button for it on every unclaimed row was permanent furniture for a one-off.
        .contextMenu {
            if unclaimed, !isYou, let claim {
                Button("This is me — sign my approvals as \(name)", action: claim)
            }
        }
    }

    private var monogram: some View {
        Circle()
            .fill(Palette.accent.opacity(isMinor ? 0.22 : 0.32))
            .frame(width: 28, height: 28)
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
    }

    @ViewBuilder
    private var first: some View {
        if isYou, let rename {
            TextField("Your name", text: rename.text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .onSubmit(rename.save)
                .help("Shown against what you approve, so other admins can see who decided what")
        } else {
            Text(name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    /// The device, and nothing else. The role used to live here and was redundant — the
    /// section heading two rows up already says whether this is an admin or a minor.
    @ViewBuilder
    private var second: some View {
        if let device = devices.first {
            Label {
                Text(device.kind.noun.capitalized + " · seen "
                     + device.lastSeen.formatted(date: .omitted, time: .shortened))
            } icon: {
                Image(systemName: device.kind.icon)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.38))
            .labelStyle(.titleAndIcon)
        } else {
            DeviceMenu(expected: expected, set: setExpected)
        }
    }

    private var removeButton: some View {
        Group {
            if isYou {
                // A blank of the same width, so your row lines up with the others.
                Color.clear.frame(width: 14, height: 14)
            } else {
                Button(action: remove) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(hovering ? 0.55 : 0.25))
                }
                .buttonStyle(.plain)
                .help("Remove " + name)
                .pointingHand()
            }
        }
        .frame(width: 14)
    }
}

/// What somebody is expected to carry, until a real device says otherwise.
///
/// No watch. The app has no watchOS target, so a watch could never report in and the row
/// would say "not seen yet" for ever — an option that can only ever be wrong is worse
/// than one that is missing. It is listed as disabled so its absence is explained rather
/// than mysterious.
private struct DeviceMenu: View {
    let expected: DeviceRecord.Kind?
    let set: (DeviceRecord.Kind?) -> Void

    var body: some View {
        Menu {
            Button("Phone") { set(.phone) }
            Button("Tablet") { set(.tablet) }
            Button("Computer") { set(.computer) }
            Divider()
            Button("Watch — needs a watchOS app") {}.disabled(true)
            if expected != nil {
                Divider()
                Button("Clear") { set(nil) }
            }
        } label: {
            HStack(spacing: 4) {
                if let expected {
                    Image(systemName: expected.icon)
                        .font(.system(size: 10.5))
                    Text("Not seen yet")
                        .font(.system(size: 10.5))
                } else {
                    Text("Set device")
                        .font(.system(size: 10.5))
                }
            }
            .foregroundStyle(.white.opacity(0.32))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .help(expected == nil
              ? "Record what this person carries — the device itself will confirm when it opens the app"
              : "Expected, but this device has not opened the app yet")
    }
}

/// A small + at the end of a section heading. Quiet until hovered, like everything else
/// on this panel.
private struct AddButton: View {
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.45))
                .frame(width: 20, height: 20)
                .background(.white.opacity(hovering ? 0.12 : 0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .pointingHand()
    }
}
