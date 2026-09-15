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
                Text(shelf.folder?.lastPathComponent ?? "Not chosen")
                    .font(.system(size: 13))
                    .foregroundStyle(shelf.folder == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Children")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)

            ForEach(shelf.roster, id: \.id) { minor in
                HStack {
                    Image(systemName: "person.crop.circle").foregroundStyle(Palette.accent)
                    Text(minor.name)
                    Spacer()
                    Text("\(shelf.approved(for: minor.id).count) approved")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            HStack {
                TextField("Add a child…", text: $childName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addChild)
                Button("Add", action: addChild)
                    .disabled(working || childName.trimmingCharacters(in: .whitespaces).isEmpty)
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
