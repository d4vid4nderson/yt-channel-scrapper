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

    private var profiles: Profiles { model.profiles }
    private var shelf: ShelfStore { model.shelf }

    var body: some View {
        NavigationStack {
            List {
                you
                folder
                if profiles.guardian != nil, shelf.folder != nil { children }
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
            .alert(newIsMinor ? "Add a child" : "Add a parent", isPresented: $addingChild) {
                TextField("Their name", text: $childName)
                    .textInputAutocapitalization(.words)
                Button("Add") { addChild() }
                    .disabled(childName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { childName = "" }
            } message: {
                Text(newIsMinor
                     ? "A name only — it is how you will tell their shelves apart. Nothing "
                        + "is sent to them and nobody has to accept anything."
                     : "This creates the identity their approvals will be signed with. On "
                        + "their own device they pick their name here to claim it.")
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
            Text("Shown against the videos you approve, so the other parent can see who "
                 + "decided what. You can change it later without unpicking anything.")
        }
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
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

    private var children: some View {
        Section {
            // Adults are listed, not added: a guardian's identity is created on their own
            // device when they name themselves, so there is nothing to create from here.
            ForEach(shelf.guardians, id: \.id) { guardian in
                HStack {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(Palette.accent)
                    Text(guardian.name).foregroundStyle(Color.primaryText)
                    Text(guardian.id == profiles.guardian?.id ? "you" : "parent")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    Spacer()
                    devices(for: guardian.id)
                    if guardian.id != profiles.guardian?.id, shelf.isUnclaimed(guardian.id) {
                        Button("This is me") { claim(guardian) }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.accent)
                            .buttonStyle(.plain)
                    }
                }
                .listRowBackground(Color.card)
                .swipeActions(edge: .trailing) {
                    if guardian.id != profiles.guardian?.id {
                        Button(role: .destructive) {
                            removing = guardian
                        } label: { Label("Remove", systemImage: "person.badge.minus") }
                    }
                }
            }

            ForEach(shelf.roster, id: \.id) { minor in
                HStack {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(Palette.accent)
                    Text(minor.name)
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    devices(for: minor.id)
                    Text("\(shelf.approved(for: minor.id).count) approved")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                }
                .listRowBackground(Color.card)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        removing = Profiles.Guardian(id: minor.id, name: minor.name)
                    } label: { Label("Remove", systemImage: "person.badge.minus") }
                }
            }

            Picker("Add", selection: $newIsMinor) {
                Text("Child").tag(true)
                Text("Parent").tag(false)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Button(newIsMinor ? "Add a child…" : "Add a parent…",
                   systemImage: "person.badge.plus") {
                childName = ""
                addingChild = true
            }
            .disabled(working)
            .listRowBackground(Color.card)
        } header: {
            header("Children")
        } footer: {
            Text("Another parent appears here once they open the app, name themselves and "
                 + "pick this same folder — nothing to invite or accept. Device icons show "
                 + "only devices running this app; there is no way to read the devices on "
                 + "an Apple ID.")
        }
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
