import AppKit
import SwiftUI

/// Make a plugged-in phone a child's, from start to finish.
///
/// Four answers, one button: which phone, which child (or a new one), the PIN a parent
/// will use to get back out, and the app file to put on it. Then the Mac installs the
/// app, tells the phone whose it is, and opens it — already locked in Minor Mode, never
/// having been anybody's adult phone along the way.
///
/// The one thing left for the phone is choosing the family folder, once. iOS gives an
/// app no way to reach a shared iCloud Drive folder without the person picking it, and
/// no way for another device to pick it for them. The sheet ends by saying exactly
/// which folder that is.
struct PhoneSetupSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var phones: [PhoneDeployer.Phone] = []
    @State private var looking = true
    @State private var phoneID: String?
    /// Nil means "a new child", named in `newName`.
    @State private var minorID: UUID?
    @State private var newName = ""
    /// Set by the pad once it has been entered twice and matched.
    @State private var pin: String?
    @State private var ipa: AppFile?
    @State private var lookingForApp = true
    @State private var step: Step = .ready

    enum Step: Equatable {
        case ready
        case working(String)
        case done(child: String)
        case failed(String)
    }

    private var shelf: ShelfStore { model.shelf }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.ink(0.08))
            Group {
                switch step {
                case .done(let child): finished(child: child)
                default: form
                }
            }
            .padding(22)
            Divider().overlay(Palette.ink(0.08))
            footer
        }
        .frame(width: 720)
        .background(Palette.sheetSurface)
        .task { await findPhones() }
        .task { await findApp() }
        // The family list can finish loading after the sheet opens; without this the
        // picker sat on "New child…" and invited a second copy of a child who exists.
        .onChange(of: shelf.roster) { _, roster in
            if minorID == nil, newName.isEmpty, let first = roster.first { minorID = first.id }
        }
    }

    // MARK: - Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Set up a child's phone")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink(1))
            Text("Installs the app and locks it to one child, over the cable.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink(0.45))
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var form: some View {
        HStack(alignment: .top, spacing: 24) {
            details
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Palette.ink(0.08)).frame(width: 1)
            PINEntry(pin: $pin)
                .disabled(isWorking)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Phone") {
                if looking {
                    ProgressView().controlSize(.small)
                } else if phones.isEmpty {
                    Text("None found. Plug the phone in with a cable and unlock it.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink(0.5))
                } else {
                    Picker("", selection: $phoneID) {
                        ForEach(phones) { phone in
                            Text(phone.isWired ? "\(phone.name) — on the cable" : phone.name)
                                .tag(Optional(phone.id))
                        }
                    }
                    .labelsHidden()
                }
                Button {
                    Task { await findPhones() }
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Look again")
            }

            row("Child") {
                Picker("", selection: $minorID) {
                    ForEach(shelf.roster, id: \.id) { minor in
                        Text(minor.name).tag(Optional(minor.id))
                    }
                    if !shelf.roster.isEmpty { Divider() }
                    Text("New child…").tag(UUID?.none)
                }
                .labelsHidden()
                .frame(width: 160)
                if minorID == nil {
                    TextField("Their name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            row("App") { appCard }

            if let problem {
                note(problem, symbol: "info.circle", tint: Palette.ink(0.5))
            }
            switch step {
            case .working(let what):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(what).font(.system(size: 12)).foregroundStyle(Palette.ink(0.75))
                }
            case .failed(let message):
                note(message, symbol: "exclamationmark.triangle.fill", tint: Palette.warn)
            default:
                EmptyView()
            }
        }
    }

    /// The app file, found rather than asked for. The newest build on the Mac is almost
    /// always the one wanted, so it is picked and described — when it was built, and
    /// where — with a way to choose another for the rare time it is not.
    @ViewBuilder
    private var appCard: some View {
        if lookingForApp {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for the app…").font(.system(size: 12)).foregroundStyle(Palette.ink(0.5))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let ipa {
                    HStack(spacing: 8) {
                        Image(systemName: "app.badge.checkmark")
                            .foregroundStyle(Palette.good)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Command Center for iPhone")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Palette.ink(0.9))
                            Text("Built \(ipa.built.formatted(.relative(presentation: .named))) · "
                                 + ipa.url.deletingLastPathComponent().lastPathComponent)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.ink(0.45))
                        }
                    }
                    .help(ipa.url.path)
                } else {
                    Text("No iPhone app found on this Mac. Build one with ios/release.sh --adhoc, or choose the file.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    Button(ipa == nil ? "Choose…" : "Choose another…", action: chooseIPA)
                    if let ipa {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([ipa.url])
                        }
                        .buttonStyle(.link)
                    }
                }
                .font(.system(size: 11.5))
            }
        }
    }

    private func finished(child: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            note("The phone is now \(child)'s, locked in Minor Mode.",
                 symbol: "checkmark.circle.fill", tint: Palette.good)
            // The phone never replaces a PIN it already has — see `Profiles.apply` — and
            // it has no way to tell this Mac which case it was.
            note("If the phone already had a PIN, that one still unlocks it rather than "
                 + "the one typed here.", symbol: "lock", tint: Palette.ink(0.5))
            Text("One step left, on the phone")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink(0.85))
            Text("Tap **Connect the family folder** and choose "
                 + "**\(shelf.folder?.lastPathComponent ?? "the family folder")**. "
                 + "It has to be shared with the Apple ID signed in on that phone — "
                 + "share it from Finder first if it is not. After that, whatever you drop "
                 + "on \(child) here arrives whenever the app is opened.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if case .done = step {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button("Set Up Phone") { Task { await setUp() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.ink(0.55))
                .frame(width: 52, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func note(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - State

    private var isWorking: Bool { if case .working = step { true } else { false } }

    private var pinIsValid: Bool { pin != nil }

    private var childName: String {
        if let minorID, let minor = shelf.roster.first(where: { $0.id == minorID }) { return minor.name }
        return newName.trimmingCharacters(in: .whitespaces)
    }

    /// The first thing still missing, said once, under the form.
    private var problem: String? {
        if model.profiles.guardian == nil || shelf.folder == nil {
            return "Set up your family first (Users panel), so there is a folder to connect the phone to."
        }
        if let phone = phones.first(where: { $0.id == phoneID }), !phone.developerMode {
            return "Turn on Developer Mode on \(phone.name) first: Settings → Privacy & "
                + "Security → Developer Mode."
        }
        return nil
    }

    private var canStart: Bool {
        !isWorking && phoneID != nil && !childName.isEmpty && pinIsValid && ipa != nil
            && model.profiles.guardian != nil && shelf.folder != nil
    }

    // MARK: - Doing it

    private func findPhones() async {
        looking = true
        phones = (try? await PhoneDeployer.phones()) ?? []
        if phoneID == nil || !phones.contains(where: { $0.id == phoneID }) {
            phoneID = phones.first?.id
        }
        if minorID == nil, newName.isEmpty, let first = shelf.roster.first { minorID = first.id }
        looking = false
    }

    private func findApp() async {
        lookingForApp = true
        ipa = await AppFile.newest()
        lookingForApp = false
    }

    private func chooseIPA() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "ipa") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the iPhone app. ios/release.sh --adhoc puts it in ios/build/export."
        if let ipa { panel.directoryURL = ipa.url.deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ipa = AppFile(url: url)
        UserDefaults.standard.set(url.path, forKey: AppFile.rememberedKey)
    }

    private func setUp() async {
        guard let guardian = model.profiles.guardian,
              let phone = phones.first(where: { $0.id == phoneID }),
              let ipa = ipa?.url,
              let pin
        else { return }

        do {
            // The child first: if the phone step fails, they still exist to send to,
            // and running this again finds them in the picker rather than making a twin.
            let minor: Profiles.Minor
            if let minorID, let existing = shelf.roster.first(where: { $0.id == minorID }) {
                minor = existing
            } else if let existing = shelf.roster.first(where: {
                $0.name.localizedCaseInsensitiveCompare(childName) == .orderedSame
            }) {
                // "New child" with the name of one who is already here is that child.
                minor = existing
            } else {
                step = .working("Adding \(childName) to the family…")
                guard let member = await shelf.createPerson(named: childName, isMinor: true, as: guardian)
                else { throw PhoneDeployer.Failure(message: shelf.problem ?? "\(childName) could not be added.") }
                minor = Profiles.Minor(id: member.id, name: member.name)
                minorID = member.id
            }

            step = .working("Reading the app file…")
            let bundleID = try await PhoneDeployer.bundleID(of: ipa)

            step = .working("Installing the app on \(phone.name)…")
            try await PhoneDeployer.install(ipa, on: phone)

            let setup = ChildSetup(minor: minor, pin: pin, folderName: shelf.folder?.lastPathComponent)
            step = .working("Telling the phone it is \(minor.name)'s…")
            // Either route is enough on its own; the launch is the one that also makes it
            // happen now. Only both failing is a failure.
            let copied = (try? await PhoneDeployer.handOver(setup, bundleID: bundleID, to: phone)) != nil
            step = .working("Opening the app…")
            do {
                try await PhoneDeployer.launch(bundleID: bundleID, on: phone, with: setup)
            } catch where copied {
                // The file is there; it takes effect the first time the app is opened.
            }

            await shelf.setExpectedDevice(minor.id, kind: phone.model.contains("iPad") ? .tablet : .phone,
                                          as: guardian)
            model.nearby.remember(phone, isFor: minor)
            self.pin = nil
            step = .done(child: minor.name)
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

}

/// The iPhone app's signed file, and when it was made.
struct AppFile: Equatable {
    let url: URL
    let built: Date

    init(url: URL) {
        self.url = url
        self.built = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast
    }

    static let rememberedKey = "phoneSetup.ipaPath"
    static let filename = "YTChannelScraper.ipa"

    /// The newest copy of the app anywhere this Mac can see.
    ///
    /// Newest rather than last-used: `release.sh --adhoc` overwrites its output in place,
    /// but a build made from a second checkout lands somewhere else, and an old file
    /// installed over a new app is the one mistake here that is easy to make and hard
    /// to notice. Spotlight finds copies anywhere; the paths below cover a Mac where it
    /// has not indexed the build folder yet.
    static func newest() async -> AppFile? {
        var paths = Set<String>()
        if let remembered = UserDefaults.standard.string(forKey: rememberedKey) { paths.insert(remembered) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for root in ["Personal", "Developer", "Documents", "Downloads", "Projects", "Code", ""] {
            paths.insert("\(home)/\(root)/YT-Channel-Scraper/ios/build/export/\(filename)")
        }
        paths.formUnion(await spotlight())

        return paths
            .filter { $0.hasSuffix(".ipa") && FileManager.default.fileExists(atPath: $0) }
            .map { AppFile(url: URL(fileURLWithPath: $0)) }
            .max { $0.built < $1.built }
    }

    private static func spotlight() async -> [String] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["-name", filename]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n").map(String.init)
                // Not the copies inside an Xcode archive or the Trash.
                .filter { !$0.contains("/.Trash/") && !$0.contains(".xcarchive/") }
        }.value
    }
}
