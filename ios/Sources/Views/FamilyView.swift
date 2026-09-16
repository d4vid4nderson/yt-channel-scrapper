import SwiftUI
import UniformTypeIdentifiers

/// Who you are, where the shared folder is, and who you are curating for.
///
/// Nothing else in the guardian feature works until this screen has been used once:
/// approvals are signed with a guardian id, they are written into a folder, and they are
/// addressed to a child. All three come from here.
///
/// The folder is picked by hand and cannot be otherwise. iOS has no API to create a
/// shared iCloud Drive folder or invite anyone to one — sharing is something a person
/// does in Files.app. So the flow is: one guardian makes a folder and shares it with the
/// other, and each device points at it here, once.
struct FamilyView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var picking = false
    @State private var addingChild = false
    @State private var childName = ""
    @State private var newIsMinor = true
    @State private var working = false
    @State private var removing: Profiles.Guardian?
    @State private var claiming: Profiles.Guardian?
    /// An existing admin whose name matches what was just typed. Offered rather than
    /// silently accepted: typing a name that already exists is how a person ends up as
    /// two people, one per device, with half their things sent to each.
    @State private var sameName: Profiles.Guardian?
    @State private var showingInbox = false

    private var profiles: Profiles { model.profiles }
    private var shelf: ShelfStore { model.shelf }

    var body: some View {
        NavigationStack {
            List {
                you
                folder
                if profiles.guardian != nil, shelf.folder != nil {
                    people
                    if !profiles.isMinor { inbox }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ground()
            .navigationTitle("Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.folder],
                          allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                if shelf.adopt(url) {
                    Task { await model.syncShelf() }
                }
            }
            .alert(newIsMinor ? "Add a minor" : "Add an admin", isPresented: $addingChild) {
                TextField("Their name", text: $childName)
                    .textInputAutocapitalization(.words)
                Button("Add") { addChild() }
                    .disabled(childName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { childName = "" }
            } message: {
                Text(newIsMinor
                     ? "A name only — it is how you will tell their shelves apart. Nothing "
                        + "is sent to them and nobody has to accept anything."
                     : "This creates the identity their approvals are signed with. On their "
                        + "own device they tap “This is me” to claim it.")
            }
            .alert("\(sameName?.name ?? "") is already here",
                   isPresented: Binding(get: { sameName != nil },
                                        set: { if !$0 { sameName = nil } })) {
                Button("That's me — use it") {
                    if let existing = sameName { claim(existing) }
                    sameName = nil
                }
                Button("Make a separate person") {
                    _ = profiles.setGuardianName(name.trimmingCharacters(in: .whitespaces))
                    sameName = nil
                }
                Button("Cancel", role: .cancel) {
                    name = profiles.guardian?.name ?? ""
                    sameName = nil
                }
            } message: {
                Text("Somebody with that name is already in this family, on another "
                     + "device. Use it and both devices are the same person, so anything "
                     + "sent to them reaches here too. Make a separate person only if "
                     + "this is genuinely somebody else with the same name.")
            }
            .alert("Sign as \(claiming?.name ?? "")?",
                   isPresented: Binding(get: { claiming != nil },
                                        set: { if !$0 { claiming = nil } })) {
                Button("This is me") {
                    if let target = claiming { claim(target) }
                    claiming = nil
                }
                Button("Cancel", role: .cancel) { claiming = nil }
            } message: {
                Text("This device takes on that identity, so anything you approve is "
                     + "signed with it and anything sent to them arrives here. Use it "
                     + "when the person is you on another device — not to act as "
                     + "somebody else.")
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
            .sheet(isPresented: $showingInbox) { InboxView(model: model) }
            .task {
                name = profiles.guardian?.name ?? ""
                await model.syncShelf()
            }
        }
    }

    // MARK: - You

    private var you: some View {
        Section {
            HStack {
                TextField("Your name", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { saveName() }
                if name.trimmingCharacters(in: .whitespaces) != (profiles.guardian?.name ?? "") {
                    Button("Save") { saveName() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
            }
            .listRowBackground(Color.card)
        } header: {
            header("You")
        } footer: {
            // The id behind the name is what every approval is signed with, so the name
            // being editable costs nothing.
            Text("Shown against what you approve, so other admins can see who decided "
                 + "what. You can change it later without unpicking anything.")
        }
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Somebody with this name is already in the folder and it is not this device.
        // Almost always that is the same person on their other device, and taking a new
        // identity would split them in two — half of what gets sent to "David" arriving
        // on the Mac and half on the phone, which is exactly what happened here.
        if let existing = shelf.guardians.first(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
                && $0.id != profiles.guardian?.id
        }) {
            sameName = existing
            return
        }

        if !profiles.setGuardianName(trimmed) {
            model.banner = "That name could not be saved."
        }
    }

    // MARK: - The folder

    private var folder: some View {
        Section {
            if let url = shelf.folder {
                LabeledContent("Folder", value: url.lastPathComponent)
                    .listRowBackground(Color.card)
                Button("Choose a different folder…", systemImage: "folder") { picking = true }
                    .listRowBackground(Color.card)
                Button("Stop using this folder", systemImage: "folder.badge.minus", role: .destructive) {
                    shelf.forgetFolder()
                }
                .listRowBackground(Color.card)
            } else {
                Button("Choose the shared folder…", systemImage: "folder.badge.plus") {
                    picking = true
                }
                .font(.system(size: 15, weight: .medium))
                .listRowBackground(Color.card)
            }

            if let problem = shelf.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
                    .listRowBackground(Color.card)
            }
        } header: {
            header("Shared folder")
        } footer: {
            if shelf.folder == nil {
                Text("In Files, make a folder in iCloud Drive and share it with the other "
                     + "parent. Then pick it here, on each device. iOS has no way for an "
                     + "app to create or share that folder, so this part is done by hand "
                     + "— once.")
            } else {
                Text(lastReadText)
            }
        }
    }

    private var lastReadText: String {
        if shelf.isReading { return "Reading…" }
        guard let read = shelf.lastRead else { return "Not read yet." }
        return "Last read \(read.formatted(date: .omitted, time: .shortened))."
    }

    // MARK: - Children

    /// Always shown, even at zero. The badge on Home appears only when something is
    /// waiting, which is right for the toolbar and wrong here — this is the screen
    /// somebody opens *looking* for it.
    private var inbox: some View {
        Section {
            Button {
                showingInbox = true
            } label: {
                HStack {
                    Label("Sent to you", systemImage: "tray")
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Text("\(model.inboxCount)")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(model.inboxCount > 0 ? Palette.accent : Color.secondaryText)
                }
            }
            .listRowBackground(Color.card)
        } footer: {
            Text("Things other admins have sent you wait here until you keep them. "
                 + "Anything already on your shelves is not listed.")
        }
    }

    /// Admins and minors, headed separately — they are read for different reasons and
    /// mixing them under one heading made the heading a lie.
    private var people: some View {
        Group {
            Section {
                ForEach(shelf.guardians, id: \.id) { guardian in
                    person(name: guardian.name,
                           id: guardian.id,
                           isMinor: false,
                           isYou: guardian.id == profiles.guardian?.id,
                           trailing: nil)
                        .swipeActions(edge: .trailing) {
                            if guardian.id != profiles.guardian?.id {
                                Button(role: .destructive) { removing = guardian } label: {
                                    Label("Remove", systemImage: "person.badge.minus")
                                }
                            }
                        }
                }
                Button("Add an admin…", systemImage: "person.badge.plus") {
                    childName = ""
                    newIsMinor = false
                    addingChild = true
                }
                .disabled(working)
                .listRowBackground(Color.card)
            } header: {
                header("Admins")
            } footer: {
                Text("Another admin appears once they name themselves and pick this same "
                     + "folder. On their own device they tap “This is me” to take on the "
                     + "identity rather than making a second one with the same name.")
            }

            Section {
                ForEach(shelf.roster, id: \.id) { minor in
                    person(name: minor.name,
                           id: minor.id,
                           isMinor: true,
                           isYou: false,
                           trailing: "\(shelf.approved(for: minor.id).count) sent")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removing = Profiles.Guardian(id: minor.id, name: minor.name)
                            } label: { Label("Remove", systemImage: "person.badge.minus") }
                        }
                }
                Button("Add a minor…", systemImage: "person.badge.plus") {
                    childName = ""
                    newIsMinor = true
                    addingChild = true
                }
                .disabled(working)
                .listRowBackground(Color.card)
            } header: {
                header("Minors")
            } footer: {
                Text(shelf.roster.isEmpty
                     ? "A minor appears on every admin's device as soon as iCloud catches up."
                     : "To hand a phone over, set it up as that minor under Minor Mode.")
            }
        }
    }

    /// One row: who they are, what they carry, and — for anybody but you — a way to take
    /// on their identity on this device.
    private func person(name: String, id: UUID, isMinor: Bool, isYou: Bool,
                        trailing: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isMinor ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                .foregroundStyle(Palette.accent)
            Text(name).foregroundStyle(Color.primaryText)
            if isYou {
                Text("you")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            Spacer()
            devices(for: id)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }
            if !isYou, !isMinor {
                Button("This is me") { claiming = Profiles.Guardian(id: id, name: name) }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.plain)
            }
        }
        .listRowBackground(Color.card)
    }

    /// One glyph per device that has announced itself as this person's. Only devices
    /// running this app can appear — Apple publishes no way to read the devices on an
    /// Apple ID — so somebody with none shows nothing rather than a placeholder.
    @ViewBuilder
    private func devices(for person: UUID) -> some View {
        ForEach(shelf.devices.filter { $0.personID == person }) { device in
            Image(systemName: device.kind.icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondaryText)
        }
    }

    /// Take on an identity another parent created here, rather than minting a second one
    /// with the same name — which would file this person's approvals under a different
    /// author and show them twice in the list.
    private func claim(_ guardian: Profiles.Guardian) {
        guard profiles.adopt(guardian) else { return }
        name = guardian.name
        Task {
            await shelf.markClaimed(guardian.id, as: guardian)
            await model.syncShelf()
        }
    }

    private func confirmRemove() {
        guard let target = removing, let guardian = profiles.guardian else { return }
        removing = nil
        Task {
            if await shelf.removePerson(target.id, as: guardian) == false {
                model.banner = shelf.problem ?? "That person could not be removed."
            }
        }
    }

    private func addChild() {
        guard let guardian = profiles.guardian else { return }
        let wanted = childName
        let isMinor = newIsMinor
        childName = ""
        working = true
        Task {
            if await shelf.createPerson(named: wanted, isMinor: isMinor, as: guardian) == nil {
                model.banner = shelf.problem ?? "That person could not be added."
            }
            working = false
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .textCase(nil)
    }
}
