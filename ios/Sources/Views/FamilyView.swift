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
    @State private var working = false

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
            .alert("Add a child", isPresented: $addingChild) {
                TextField("Their name", text: $childName)
                    .textInputAutocapitalization(.words)
                Button("Add") { addChild() }
                    .disabled(childName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { childName = "" }
            } message: {
                Text("A name only — it is how you will tell their shelves apart. Nothing "
                     + "is sent to them and nobody has to accept anything.")
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
            ForEach(shelf.roster, id: \.id) { minor in
                HStack {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(Palette.accent)
                    Text(minor.name)
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Text("\(shelf.approved(for: minor.id).count) approved")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                }
                .listRowBackground(Color.card)
            }

            Button("Add a child…", systemImage: "person.badge.plus") {
                childName = ""
                addingChild = true
            }
            .disabled(working)
            .listRowBackground(Color.card)
        } header: {
            header("Children")
        } footer: {
            Text(shelf.roster.isEmpty
                 ? "Add a child and they appear on both parents' devices as soon as "
                    + "iCloud catches up. There is nothing to invite or accept."
                 : "To hand a phone over, set it up as that child under Minor Mode.")
        }
    }

    private func addChild() {
        guard let guardian = profiles.guardian else { return }
        let wanted = childName
        childName = ""
        working = true
        Task {
            if await shelf.createMinor(named: wanted, as: guardian) == nil {
                model.banner = shelf.problem ?? "That child could not be added."
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
