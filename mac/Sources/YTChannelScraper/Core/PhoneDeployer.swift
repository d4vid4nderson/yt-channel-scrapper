import Foundation

/// Putting the iPhone app on a child's phone, from this Mac, over the cable.
///
/// Everything goes through `xcrun devicectl`, the tool Xcode itself uses. Nothing else
/// Apple ships will install an app on a phone from the command line, which is why this
/// needs Xcode on the Mac — not just the command-line tools — and why it says so plainly
/// when that is missing rather than failing somewhere later.
///
/// Three steps, in order:
///
/// 1. **Install** the signed `.ipa` that `ios/release.sh --adhoc` makes. It is signed
///    only for the phones registered on the developer account, so a phone that is not
///    on it gets a clear refusal here rather than an icon that will not open.
/// 2. **Hand over** a `ChildSetup` naming the child and carrying the PIN, as a file in
///    the app's Documents folder.
/// 3. **Launch** the app, with the same setup on its command line. The launch is what
///    makes it take effect now rather than the next time somebody opens the app, and
///    the argument is the fallback for a phone that refuses the file copy.
enum PhoneDeployer {
    struct Phone: Identifiable, Hashable, Sendable {
        let id: String            // UDID
        let name: String
        let model: String
        let isWired: Bool
        let developerMode: Bool
        /// On the cable, or answering on the network. False for a phone that is paired
        /// but switched off or out of range.
        let isReachable: Bool
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")

    /// Whether this Mac has a `devicectl` to talk to phones with.
    static func isAvailable() async -> Bool {
        (try? await run(["--find", "devicectl"])) != nil
    }

    /// iPhones and iPads that are plugged in or reachable, paired with this Mac, and real.
    static func phones() async throws -> [Phone] {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytcs-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: out) }
        _ = try await run(["devicectl", "list", "devices", "--quiet", "--json-output", out.path])

        let data = try Data(contentsOf: out)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let devices = (root?["result"] as? [String: Any])?["devices"] as? [[String: Any]] ?? []

        return devices.compactMap { device in
            let hardware = device["hardwareProperties"] as? [String: Any] ?? [:]
            let properties = device["deviceProperties"] as? [String: Any] ?? [:]
            let connection = device["connectionProperties"] as? [String: Any] ?? [:]
            guard hardware["reality"] as? String == "physical",
                  hardware["platform"] as? String == "iOS",
                  connection["pairingState"] as? String == "paired",
                  let udid = hardware["udid"] as? String
            else { return nil }
            return Phone(
                id: udid,
                name: properties["name"] as? String ?? "iPhone",
                model: hardware["marketingName"] as? String ?? "",
                isWired: connection["transportType"] as? String == "wired",
                developerMode: properties["developerModeStatus"] as? String == "enabled",
                isReachable: connection["tunnelState"] as? String != "unavailable"
                    && connection["transportType"] != nil
                    && !(connection["transportType"] is NSNull)
            )
        }
        // The one on the cable first: that is the phone being set up.
        .sorted { ($0.isWired ? 0 : 1, $0.name) < ($1.isWired ? 0 : 1, $1.name) }
    }

    /// The bundle identifier inside an `.ipa`, which is what every later step addresses
    /// the app by. Read from the file rather than assumed, so a build signed under a
    /// different id still works.
    static func bundleID(of ipa: URL) async throws -> String {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytcs-ipa-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        _ = try await run(["unzip", "-q", "-o", ipa.path, "Payload/*.app/Info.plist", "-d", temp.path],
                          executable: URL(fileURLWithPath: "/usr/bin/env"))

        let payload = temp.appendingPathComponent("Payload")
        guard let app = try FileManager.default.contentsOfDirectory(atPath: payload.path)
                .first(where: { $0.hasSuffix(".app") }),
              let info = NSDictionary(contentsOf: payload.appendingPathComponent("\(app)/Info.plist")),
              let id = info["CFBundleIdentifier"] as? String
        else { throw Failure(message: "That file is not an iPhone app (.ipa).") }
        return id
    }

    static func install(_ ipa: URL, on phone: Phone) async throws {
        _ = try await run(["devicectl", "device", "install", "app", "--device", phone.id, ipa.path])
    }

    /// Put the setup in the app's Documents folder. Throws if the phone will not allow it,
    /// which `launch` then covers.
    static func handOver(_ setup: ChildSetup, bundleID: String, to phone: Phone) async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytcs-setup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try setup.encoded().write(to: file)
        _ = try await run([
            "devicectl", "device", "copy", "to", "--device", phone.id,
            "--source", file.path,
            "--destination", "Documents/\(ChildSetup.filename)",
            "--domain-type", "appDataContainer",
            "--domain-identifier", bundleID,
        ])
    }

    /// Open the app on the phone, carrying the setup, and replacing any copy that is
    /// already running so the new one reads it.
    static func launch(bundleID: String, on phone: Phone, with setup: ChildSetup) async throws {
        let argument = try setup.encoded().base64EncodedString()
        _ = try await run([
            "devicectl", "device", "process", "launch", "--device", phone.id,
            // `--` ends devicectl's own options; without it the app's argument is read
            // as one of them and the launch is refused.
            "--terminate-existing", bundleID, "--", ChildSetup.argument, argument,
        ])
    }

    /// Bring the app to the front on the phone, which is what makes it read the family
    /// folder and start fetching. Opens it where it is rather than restarting it, so
    /// whatever the child was watching is not cut off.
    static func open(bundleID: String, on phone: Phone) async throws {
        _ = try await run(["devicectl", "device", "process", "launch", "--device", phone.id,
                           "--activate", bundleID])
    }

    // MARK: - Delivering the family folder

    /// Where on the phone a delivered copy of the family folder lives: hidden, inside the
    /// app's Documents, which `LocalFiles` and Files.app both skip.
    static let deliveredFolder = "Documents/.family"

    /// Hand the phone a copy of the family folder — the shelves and the family list, not
    /// the devices' own reports, which each device writes about itself.
    ///
    /// Replaces the whole copy each time, so a decision withdrawn here is withdrawn there;
    /// a copy that only ever grew could not carry a veto.
    static func deliver(familyFolder: URL, bundleID: String, to phone: Phone) async throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytcs-family-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let opened = familyFolder.startAccessingSecurityScopedResource()
        defer { if opened { familyFolder.stopAccessingSecurityScopedResource() } }
        let names = try FileManager.default.contentsOfDirectory(
            at: familyFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for url in names where url.pathExtension.lowercased() == "json"
            && !url.lastPathComponent.hasPrefix(DeviceRecord.prefix) {
            try FileManager.default.copyItem(at: url, to: staging.appendingPathComponent(url.lastPathComponent))
        }

        _ = try await run([
            "devicectl", "device", "copy", "to", "--device", phone.id,
            "--source", staging.path,
            "--destination", deliveredFolder,
            "--domain-type", "appDataContainer",
            "--domain-identifier", bundleID,
            "--remove-existing-content", "true",
        ])
    }

    /// The reports the phone has written about itself into its delivered copy, as raw
    /// bytes for `ShelfStore.relay`. Empty when there is no copy yet.
    static func collectReports(bundleID: String, from phone: Phone) async -> [Data] {
        let landing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytcs-reports-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: landing) }
        try? FileManager.default.createDirectory(at: landing, withIntermediateDirectories: true)
        do {
            _ = try await run([
                "devicectl", "device", "copy", "from", "--device", phone.id,
                "--source", deliveredFolder,
                "--destination", landing.path,
                "--domain-type", "appDataContainer",
                "--domain-identifier", bundleID,
            ])
        } catch {
            return []
        }
        let found = FileManager.default.enumerator(at: landing, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        return found
            .filter { $0.lastPathComponent.hasPrefix(DeviceRecord.prefix) && $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
    }

    /// Delete the app from the phone. Its Documents go with it — the delivered family
    /// folder and anything downloaded — which is the point: nothing of the child's setup
    /// is left behind.
    static func uninstall(bundleID: String, from phone: Phone) async throws {
        _ = try await run(["devicectl", "device", "uninstall", "app", "--device", phone.id, bundleID])
    }

    // MARK: - Which phone is whose

    /// Which child each phone was set up for, by UDID.
    ///
    /// The family folder knows devices by an id the app makes up on the phone, and the
    /// cable knows them by UDID; nothing links the two. This Mac set the phone up, so it
    /// writes down the answer then, and a phone that turns up on the cable or the network
    /// later can be shown under the right name.
    private static let ownersKey = "phoneSetup.childByPhone"

    static func remember(_ phone: Phone, isFor minor: Profiles.Minor) {
        var owners = UserDefaults.standard.dictionary(forKey: ownersKey) as? [String: String] ?? [:]
        owners[phone.id] = minor.id.uuidString
        UserDefaults.standard.set(owners, forKey: ownersKey)
    }

    static func forget(_ phoneID: String) {
        var owners = UserDefaults.standard.dictionary(forKey: ownersKey) as? [String: String] ?? [:]
        owners[phoneID] = nil
        UserDefaults.standard.set(owners, forKey: ownersKey)
    }

    static func owners() -> [String: UUID] {
        let raw = UserDefaults.standard.dictionary(forKey: ownersKey) as? [String: String] ?? [:]
        return raw.compactMapValues(UUID.init(uuidString:))
    }

    // MARK: - Running the tool

    /// Run a command and return its output, or throw with the line of it that explains
    /// the failure. `devicectl` buries the useful sentence under a stack of error domains.
    private static func run(_ arguments: [String], executable: URL = xcrun) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            // Read before waiting: a full pipe blocks the child, and it would never exit.
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(decoding: outData, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                let text = String(decoding: errData, as: UTF8.self) + output
                throw Failure(message: explain(text))
            }
            return output
        }.value
    }

    /// The one sentence a person can act on, out of whatever `devicectl` printed.
    static func explain(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("device was still locked") || lower.contains("device is currently locked") {
            return "The phone is locked. Unlock it, stay on the Home Screen, and try again."
        }
        if lower.contains("developer mode is not enabled") {
            return "Turn on Developer Mode on the phone: Settings → Privacy & Security → "
                + "Developer Mode, then let it restart."
        }
        if lower.contains("unable to find devicectl") || lower.contains("devicectl: not found")
            || lower.contains("xcrun: error") {
            return "Setting up a phone needs Xcode installed on this Mac."
        }
        if lower.contains("-10814") || lower.contains("application not found")
            || lower.contains("not installed") {
            return "The app is not on this phone yet. Use Set up a child's phone to put it there."
        }
        if lower.contains("provisioning profile") || lower.contains("0xe8008012")
            || lower.contains("not included in the provisioning") {
            return "This phone is not in the app's signing profile. Register it on the "
                + "developer account, then rebuild with ios/release.sh --adhoc."
        }
        // Otherwise the last line that reads like an explanation.
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let reason = lines.last { $0.hasPrefix("NSLocalizedFailureReason") || $0.contains("error:") }
            ?? lines.first { !$0.isEmpty }
        return reason.map { String($0).replacingOccurrences(of: "NSLocalizedFailureReason = ", with: "") }
            ?? "The phone did not respond."
    }
}
