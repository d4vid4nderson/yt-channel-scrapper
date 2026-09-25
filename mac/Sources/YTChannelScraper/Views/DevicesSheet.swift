import SwiftUI

/// Every device in the family and what each one is holding, the computer included.
///
/// The board answers "has it landed?" with a number. This answers the question behind
/// it — *what exactly is on Wyatt's phone?* — from the reports each device writes about
/// itself: what its shelf allows, what files are on its disk, how much room is left.
///
/// Also where the list gets tidied. Every reinstall of the phone app used to leave its
/// old record behind, so a child could show two identical phones; those, and anything
/// silent for a month, are offered for cleanup here. Removing is a tombstone rather than
/// a deletion — see `ForgottenDevice` — so a device that is actually still in use simply
/// reappears the next time it reports.
struct DevicesSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selection: UUID?
    @State private var confirmingCleanup = false
    @State private var confirmingRemove: DeviceRecord?

    private var shelf: ShelfStore { model.shelf }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.ink(0.08))
            if shelf.devices.isEmpty {
                Text("No device has reported in yet. Each one appears here after it opens the app with the family folder chosen.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            } else {
                HStack(spacing: 0) {
                    list
                        .frame(width: 250)
                    Divider().overlay(Palette.ink(0.08))
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            Divider().overlay(Palette.ink(0.08))
            footer
        }
        .frame(width: 820, height: 580)
        .background(Palette.sheetSurface)
        .onAppear {
            if selection == nil { selection = model.focusedDevice ?? shelf.devices.first?.id }
        }
        .task { await model.syncShelf() }
        .confirmationDialog(cleanupTitle, isPresented: $confirmingCleanup) {
            Button("Remove \(shelf.clutter.count)", role: .destructive) {
                forget(shelf.clutter)
            }
        } message: {
            Text(cleanupMessage)
        }
        .confirmationDialog("Remove \(confirmingRemove?.name ?? "this device")?",
                            isPresented: Binding(get: { confirmingRemove != nil },
                                                 set: { if !$0 { confirmingRemove = nil } })) {
            Button("Remove", role: .destructive) {
                if let record = confirmingRemove { forget([record]) }
            }
        } message: {
            Text("It comes off the list on every device. If it is still in use, it comes back the next time it syncs.")
        }
    }

    // MARK: - Header and footer

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Devices")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink(1))
                Text("What each device holds, as it last reported.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink(0.45))
            }
            Spacer()
            if !shelf.clutter.isEmpty {
                Button {
                    confirmingCleanup = true
                } label: {
                    Label("Clean up \(shelf.clutter.count)", systemImage: "sparkles")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .help(cleanupMessage)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack {
            if let read = shelf.lastRead {
                Text("Read " + read.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink(0.35))
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - The list

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
        return [("Admins", admin), ("Minors", minor), ("Not attached to anyone", other)]
            .filter { !$0.1.isEmpty }
            .map { ($0.0, $0.1.sorted(by: Self.order)) }
    }

    private static func order(_ a: DeviceRecord, _ b: DeviceRecord) -> Bool {
        let left = (a.personName ?? "", a.kind.rawValue, -a.lastSeen.timeIntervalSince1970)
        let right = (b.personName ?? "", b.kind.rawValue, -b.lastSeen.timeIntervalSince1970)
        return left < right
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.ink(0.35))
                            .textCase(.uppercase)
                            .tracking(0.7)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)
                        ForEach(group.devices) { record in
                            listRow(record)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func listRow(_ record: DeviceRecord) -> some View {
        let selected = selection == record.id
        return Button {
            selection = record.id
        } label: {
            HStack(spacing: 9) {
                Image(systemName: record.kind.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(Palette.ink(0.55))
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.ink(0.9))
                        .lineLimit(1)
                    Text(subtitle(for: record))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.ink(0.4))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let flag = flag(for: record) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent.opacity(0.85))
                        .help(flag)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selected ? Palette.ink(0.08) : .clear, in: ThemedRect(cornerRadius: 7))
            .contentShape(ThemedRect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !shelf.isThisDevice(record) {
                Button("Remove from list…", role: .destructive) { confirmingRemove = record }
            }
        }
    }

    private func subtitle(for record: DeviceRecord) -> String {
        var parts: [String] = []
        if shelf.isThisDevice(record) { parts.append("this Mac") }
        parts.append(Self.seen(record.lastSeen))
        if let files = record.files { parts.append("\(files.count) file\(files.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    /// Why a record is offered for cleanup, if it is.
    private func flag(for record: DeviceRecord) -> String? {
        if shelf.duplicateDevices.contains(where: { $0.id == record.id }) {
            return "Looks like an older copy of another \(record.kind.noun) with the same name — left behind by a reinstall."
        }
        if shelf.staleDevices.contains(where: { $0.id == record.id }) {
            return "Not seen for over a month."
        }
        return nil
    }

    // MARK: - One device

    @ViewBuilder
    private var detail: some View {
        if let record = shelf.devices.first(where: { $0.id == selection }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summary(record)
                    if let flag = flag(for: record) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.accent)
                            Text(flag)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.ink(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button("Remove…") { confirmingRemove = record }
                        }
                        .padding(10)
                        .background(Palette.accent.opacity(0.08), in: ThemedRect(cornerRadius: 8))
                    }
                    if let owner = record.personID, record.isMinor {
                        shelfSection(for: owner)
                    }
                    filesSection(record)
                }
                .padding(22)
            }
        } else {
            Text("Pick a device")
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summary(_ record: DeviceRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: record.kind.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.ink(0.6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink(1))
                    Text([record.personName.map { ($0) + (record.isMinor ? " · minor" : " · admin") },
                          "last seen " + record.lastSeen.formatted(date: .abbreviated, time: .shortened)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink(0.45))
                }
                Spacer()
                if !shelf.isThisDevice(record), flag(for: record) == nil {
                    Button("Remove…", role: .destructive) { confirmingRemove = record }
                        .controlSize(.small)
                }
            }
            HStack(spacing: 22) {
                if record.isMinor {
                    stat("\(record.approved)", "approved")
                }
                if let files = record.files {
                    stat("\(files.count)", files.count == 1 ? "file" : "files")
                }
                if let used = record.usedBytes {
                    stat(Self.bytes(used), "used")
                }
                if let free = record.freeBytes {
                    stat(Self.bytes(free), "free")
                }
                if let library = record.library {
                    stat("\(library.channels)", "channels")
                    stat("\(library.videos)", "videos kept")
                }
            }
        }
    }

    private func shelfSection(for person: UUID) -> some View {
        let entries = shelf.approvedEntries(for: person)
        return section("On their shelf", count: entries.count,
                       empty: "Nothing approved yet. Drag a channel or video onto their device on the board.") {
            ForEach(entries, id: \.key) { entry in
                itemRow(icon: entry.kind == .channel ? "person.crop.square" : "play.rectangle",
                        title: entry.title ?? entry.id,
                        detail: "\(entry.kind == .channel ? "Channel" : "Video") · by \(entry.guardian) · "
                            + entry.at.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    @ViewBuilder
    private func filesSection(_ record: DeviceRecord) -> some View {
        if let files = record.files {
            section(record.kind == .computer ? "In the Downloads folder" : "Files on this \(record.kind.noun)",
                    count: files.count,
                    empty: record.isMinor
                        ? "No files. This phone streams what is approved rather than keeping copies."
                        : "No downloaded files.") {
                ForEach(files) { file in
                    itemRow(icon: file.isAudio ? "waveform" : "film",
                            title: file.title,
                            detail: Self.bytes(file.bytes) + " · "
                                + file.added.formatted(date: .abbreviated, time: .omitted))
                }
            }
        } else {
            section("Files", count: nil,
                    empty: "This device has not reported its files yet. It will after it is updated to the latest build and syncs.") {
                EmptyView()
            }
        }
    }

    // MARK: - Pieces

    private func section(_ title: String, count: Int?, empty: String,
                         @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.ink(0.35))
                    .textCase(.uppercase)
                    .tracking(0.7)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.ink(0.3))
                }
            }
            if count ?? 0 == 0 {
                Text(empty)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) { rows() }
                    .background(Palette.ink(0.03), in: ThemedRect(cornerRadius: 8))
                    .overlay(ThemedRect(cornerRadius: 8).strokeBorder(Palette.ink(0.05)))
            }
        }
    }

    private func itemRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(Palette.ink(0.4))
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 10)
            Text(detail)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Palette.ink(0.38))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.ink(0.9))
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.ink(0.4))
        }
    }

    private var cleanupTitle: String {
        let n = shelf.clutter.count
        return "Remove \(n) old device record\(n == 1 ? "" : "s")?"
    }

    private var cleanupMessage: String {
        let dupes = shelf.duplicateDevices.count
        let stale = shelf.clutter.count - dupes
        var parts: [String] = []
        if dupes > 0 { parts.append("\(dupes) left behind by a reinstall") }
        if stale > 0 { parts.append("\(stale) not seen for over a month") }
        return parts.joined(separator: ", ").prefix(1).uppercased()
            + parts.joined(separator: ", ").dropFirst()
            + ". Anything still in use comes back the next time it syncs."
    }

    private func forget(_ records: [DeviceRecord]) {
        guard let guardian = model.profiles.guardian else { return }
        Task {
            if await shelf.forget(records, as: guardian) {
                if let selected = selection, records.contains(where: { $0.id == selected }) {
                    selection = shelf.devices.first?.id
                }
            }
        }
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func seen(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.relative(presentation: .named))
    }
}
