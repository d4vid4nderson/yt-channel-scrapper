import SwiftUI

/// Every device in the family and what each one holds — the phone's copy of the Mac's
/// `DevicesSheet`, read from the same reports in the same shared folder.
///
/// A child's phone signed into its own Apple ID cannot write to that folder itself; the
/// Mac carries its report across on every Nearby sync. So what this shows about a child's
/// phone is as fresh as the last time the Mac could reach it, and the row says when that
/// was rather than implying it is live.
struct DevicesView: View {
    @Bindable var model: AppModel

    @State private var confirmingCleanup = false
    @State private var removing: DeviceRecord?

    private var shelf: ShelfStore { model.shelf }

    var body: some View {
        List {
            if !shelf.clutter.isEmpty {
                Section {
                    Button {
                        confirmingCleanup = true
                    } label: {
                        Label(cleanupTitle, systemImage: "sparkles")
                            .foregroundStyle(Palette.accent)
                    }
                    .listRowBackground(Color.card)
                } footer: {
                    Text(cleanupMessage)
                }
            }

            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.devices) { record in
                        NavigationLink {
                            DeviceDetailView(model: model, deviceID: record.id)
                        } label: {
                            row(record)
                        }
                        .listRowBackground(Color.card)
                        .swipeActions(edge: .trailing) {
                            if !shelf.isThisDevice(record) {
                                Button(role: .destructive) { removing = record } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                        .textCase(nil)
                }
            }

            if shelf.devices.isEmpty {
                Text("No device has reported in yet.")
                    .foregroundStyle(Color.secondaryText)
                    .listRowBackground(Color.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ground()
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.syncShelf() }
        .confirmationDialog(cleanupTitle, isPresented: $confirmingCleanup, titleVisibility: .visible) {
            Button("Remove \(shelf.clutter.count)", role: .destructive) { forget(shelf.clutter) }
        } message: {
            Text(cleanupMessage)
        }
        .confirmationDialog("Remove \(removing?.name ?? "this device")?",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let record = removing { forget([record]) }
            }
        } message: {
            Text("It comes off the list on every device. If it is still in use, it comes back the next time it syncs.")
        }
    }

    private var groups: [(title: String, devices: [DeviceRecord])] {
        let adults = Set(shelf.guardians.map(\.id))
        let children = Set(shelf.roster.map(\.id))
        var admin: [DeviceRecord] = [], minor: [DeviceRecord] = [], other: [DeviceRecord] = []
        for record in shelf.devices {
            let owner = record.personID.map { shelf.aliases[$0] ?? $0 }
            if let owner, children.contains(owner) { minor.append(record) }
            else if let owner, adults.contains(owner) { admin.append(record) }
            else { other.append(record) }
        }
        let byNewest: (DeviceRecord, DeviceRecord) -> Bool = { $0.lastSeen > $1.lastSeen }
        return [("Admins", admin), ("Minors", minor), ("Not attached to anyone", other)]
            .filter { !$0.1.isEmpty }
            .map { ($0.0, $0.1.sorted(by: byNewest)) }
    }

    private func row(_ record: DeviceRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind.icon)
                .foregroundStyle(Palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).foregroundStyle(Color.primaryText)
                Text(DeviceText.subtitle(record, isThisDevice: shelf.isThisDevice(record)))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            if shelf.clutter.contains(where: { $0.id == record.id }) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Palette.accent)
            }
        }
    }

    private var cleanupTitle: String {
        let n = shelf.clutter.count
        return "Clean up \(n) old device record\(n == 1 ? "" : "s")"
    }

    private var cleanupMessage: String {
        let dupes = shelf.duplicateDevices.count
        let stale = shelf.clutter.count - dupes
        var parts: [String] = []
        if dupes > 0 { parts.append("\(dupes) left behind by a reinstall") }
        if stale > 0 { parts.append("\(stale) not seen for over a month") }
        let joined = parts.joined(separator: ", ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
            + ". Anything still in use comes back the next time it syncs."
    }

    private func forget(_ records: [DeviceRecord]) {
        guard let guardian = model.profiles.guardian else { return }
        Task {
            if await shelf.forget(records, as: guardian) == false {
                model.banner = shelf.isDeliveredCopy
                    ? "This phone reads a copy the Mac delivered, so the list can only be tidied from the Mac or an admin's phone."
                    : (shelf.problem ?? "Those devices could not be removed.")
            }
        }
    }
}

/// One device: what its shelf allows, what is on its disk, how much room it has left.
struct DeviceDetailView: View {
    @Bindable var model: AppModel
    let deviceID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var removing = false

    private var shelf: ShelfStore { model.shelf }
    private var record: DeviceRecord? { shelf.devices.first { $0.id == deviceID } }

    var body: some View {
        List {
            if let record {
                summary(record)
                if let owner = record.personID, record.isMinor {
                    approved(for: owner)
                }
                files(record)
                if !shelf.isThisDevice(record) {
                    Section {
                        Button("Remove from list", role: .destructive) { removing = true }
                            .listRowBackground(Color.card)
                    } footer: {
                        Text("If it is still in use, it comes back the next time it syncs.")
                    }
                }
            } else {
                Text("This device is no longer on the list.")
                    .foregroundStyle(Color.secondaryText)
                    .listRowBackground(Color.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ground()
        .navigationTitle(record?.name ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove \(record?.name ?? "this device")?",
                            isPresented: $removing, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                guard let record, let guardian = model.profiles.guardian else { return }
                Task {
                    if await shelf.forget([record], as: guardian) { dismiss() }
                }
            }
        }
    }

    private func summary(_ record: DeviceRecord) -> some View {
        Section {
            line("Belongs to", record.personName.map { $0 + (record.isMinor ? " (minor)" : " (admin)") } ?? "Nobody yet")
            line("Last seen", record.lastSeen.formatted(date: .abbreviated, time: .shortened))
            if record.isMinor { line("Approved", "\(record.approved)") }
            if let used = record.usedBytes { line("Used by files", DeviceText.bytes(used)) }
            if let free = record.freeBytes { line("Free space", DeviceText.bytes(free)) }
            if let library = record.library {
                line("Library", "\(library.channels) channels · \(library.videos) videos")
            }
            if let flag = flag(for: record) {
                Label(flag, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
                    .listRowBackground(Color.card)
            }
        }
    }

    private func approved(for person: UUID) -> some View {
        let entries = shelf.approvedEntries(for: person)
        return Section {
            if entries.isEmpty {
                Text("Nothing approved yet.")
                    .foregroundStyle(Color.secondaryText)
                    .listRowBackground(Color.card)
            }
            ForEach(entries, id: \.key) { entry in
                item(icon: entry.kind == .channel ? "person.crop.square" : "play.rectangle",
                     title: entry.title ?? entry.id,
                     detail: "\(entry.kind == .channel ? "Channel" : "Video") · by \(entry.guardian) · "
                        + entry.at.formatted(date: .abbreviated, time: .omitted))
            }
        } header: {
            header("On their shelf · \(entries.count)")
        }
    }

    @ViewBuilder
    private func files(_ record: DeviceRecord) -> some View {
        Section {
            if let files = record.files {
                if files.isEmpty {
                    Text(record.isMinor
                         ? "No files. This phone streams what is approved rather than keeping copies."
                         : "No downloaded files.")
                        .foregroundStyle(Color.secondaryText)
                        .listRowBackground(Color.card)
                }
                ForEach(files) { file in
                    item(icon: file.isAudio ? "waveform" : "film",
                         title: file.title,
                         detail: DeviceText.bytes(file.bytes) + " · "
                            + file.added.formatted(date: .abbreviated, time: .omitted))
                }
            } else {
                Text("Not reported yet. It will be once this device runs the latest build and syncs.")
                    .foregroundStyle(Color.secondaryText)
                    .listRowBackground(Color.card)
            }
        } header: {
            header(record.kind == .computer ? "Downloads folder" : "Files on this \(record.kind.noun)"
                   + (record.files.map { " · \($0.count)" } ?? ""))
        }
    }

    private func flag(for record: DeviceRecord) -> String? {
        if shelf.duplicateDevices.contains(where: { $0.id == record.id }) {
            return "Looks like an older copy of another \(record.kind.noun) — left behind by a reinstall."
        }
        if shelf.staleDevices.contains(where: { $0.id == record.id }) {
            return "Not seen for over a month."
        }
        return nil
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.secondaryText)
            Spacer()
            Text(value).foregroundStyle(Color.primaryText).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 14))
        .listRowBackground(Color.card)
    }

    private func item(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.secondaryText)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .listRowBackground(Color.card)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .textCase(nil)
    }
}

enum DeviceText {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func subtitle(_ record: DeviceRecord, isThisDevice: Bool) -> String {
        var parts: [String] = []
        if isThisDevice { parts.append("this device") }
        parts.append(Calendar.current.isDateInToday(record.lastSeen)
                     ? "seen " + record.lastSeen.formatted(date: .omitted, time: .shortened)
                     : "seen " + record.lastSeen.formatted(.relative(presentation: .named)))
        if let files = record.files { parts.append("\(files.count) file\(files.count == 1 ? "" : "s")") }
        if record.isMinor { parts.append("\(record.approved) approved") }
        return parts.joined(separator: " · ")
    }
}
