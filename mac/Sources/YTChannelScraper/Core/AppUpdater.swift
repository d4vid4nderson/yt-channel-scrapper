import AppKit
import Foundation

/// Keeps the app itself current.
///
/// Separate from `Updater`, which keeps yt-dlp current and nothing else. That one drops a
/// replacement binary beside the bundle and the next scrape picks it up; this one has to
/// replace the bundle, which is a different problem with a different ending — the app
/// relaunches into the new copy.
///
/// It reads GitHub's releases, the same place the yt-dlp updater reads, and installs the
/// `.dmg` that a release carries. Downloading it here rather than through a browser also
/// sidesteps the thing that makes this app awkward to hand out: Gatekeeper refuses
/// ad-hoc-signed apps that arrive quarantined, and quarantine is set by the browser, not
/// by the network. A copy fetched in-process carries no such flag.
@MainActor
@Observable
final class AppUpdater {
    struct Release: Equatable, Sendable {
        let version: String
        let notes: String
        let asset: URL
        let published: Date?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)      // 0...1
        case installing
        case relaunching
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Set by a check the user asked for, so an "up to date" answer is shown rather than
    /// swallowed — a launch check that finds nothing should say nothing.
    private(set) var isShowingResult = false

    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

    private static let releaseAPI = URL(
        string: "https://api.github.com/repos/d4vid4nderson/yt-channel-scrapper/releases/latest"
    )!
    static let releasesPage = URL(
        string: "https://github.com/d4vid4nderson/yt-channel-scrapper/releases/latest"
    )!

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing, .relaunching: true
        default: false
        }
    }

    var updateAvailable: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// Bring the sheet up on something already found — the toolbar pill's job.
    func showResult() {
        isShowingResult = true
    }

    func dismissResult() {
        isShowingResult = false
        if case .failed = state { state = .idle }
        if case .upToDate = state { state = .idle }
    }

    // MARK: - Checking

    /// `announce` is what separates the launch check from the menu item: one puts a quiet
    /// pill in the toolbar if there is something, the other owes an answer either way.
    func check(announce: Bool = false) async {
        guard !isBusy else {
            if announce { isShowingResult = true }
            return
        }
        if announce { isShowingResult = true }
        state = .checking

        do {
            var request = URLRequest(url: Self.releaseAPI)
            request.setValue("YT-Channel-Scraper", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]]
            else { throw Failure.badResponse }

            let version = Self.number(fromTag: tag)
            guard Updater.isNewer(version, than: current) else {
                state = .upToDate
                return
            }
            guard let asset = Self.disk(in: assets) else { throw Failure.noAsset }

            state = .available(Release(
                version: version,
                notes: (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                asset: asset,
                published: (json["published_at"] as? String).flatMap {
                    ISO8601DateFormatter().date(from: $0)
                }
            ))
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// Prefer a build named for this machine's architecture, since a release may carry
    /// both; fall back to whatever single disk image is there.
    private static func disk(in assets: [[String: Any]]) -> URL? {
        let images = assets.compactMap { asset -> (name: String, url: URL)? in
            guard let name = asset["name"] as? String,
                  name.lowercased().hasSuffix(".dmg"),
                  let string = asset["browser_download_url"] as? String,
                  let url = URL(string: string)
            else { return nil }
            return (name, url)
        }
        #if arch(arm64)
        let wanted = "arm64"
        #else
        let wanted = "x86_64"
        #endif
        return (images.first { $0.name.lowercased().contains(wanted) } ?? images.first)?.url
    }

    /// Tags are written `v2.1.0`; `CFBundleShortVersionString` is not.
    static func number(fromTag tag: String) -> String {
        var text = tag.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        // "v2.1.0 — Native Mac app" and similar decorated tags.
        return text.split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? text
    }

    // MARK: - Installing

    func install() async {
        guard case .available(let release) = state else { return }

        do {
            let destination = try Self.installedBundle()
            state = .downloading(0)

            let watcher = DownloadWatcher { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(fraction)
                }
            }
            var request = URLRequest(url: release.asset)
            request.setValue("YT-Channel-Scraper", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 900

            let (downloaded, response) = try await URLSession.shared.download(
                for: request, delegate: watcher
            )
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0)
            }

            state = .installing
            let staged = try await Self.unpack(disk: downloaded, nextTo: destination)
            try Self.check(staged, isNewerThan: destination)

            // A rename, not a write: the running executable keeps the copy it was started
            // from until this process exits, so swapping the bundle underneath itself is
            // safe in a way that overwriting the files inside it would not be.
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)

            state = .relaunching
            try Self.relaunch(destination)
        } catch {
            state = .failed(Self.describe(error))
            isShowingResult = true
        }
    }

    /// Where this copy of the app actually lives, and whether it can be replaced at all.
    private static func installedBundle() throws -> URL {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { throw Failure.notABundle }
        // Running from the disk image it was downloaded in, which is read-only and is not
        // where the app is supposed to live in the first place.
        guard !bundle.path.hasPrefix("/Volumes/") else { throw Failure.runningFromDisk }
        let parent = bundle.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path),
              FileManager.default.isWritableFile(atPath: bundle.path)
        else { throw Failure.notWritable(parent.path) }
        return bundle
    }

    /// Mount the image, copy the app out of it onto the volume it is going to live on, and
    /// unmount. Copying it out first is what lets the swap be a rename.
    private static func unpack(disk image: URL, nextTo destination: URL) async throws -> URL {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory
            .appendingPathComponent("ytcs-update-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])
            try? fm.removeItem(at: mount)
        }

        try run("/usr/bin/hdiutil", [
            "attach", image.path, "-nobrowse", "-readonly", "-noverify",
            "-mountpoint", mount.path, "-quiet",
        ])

        guard let app = try fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else { throw Failure.noAppInDisk }

        let staging = try fm.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true
        )
        let staged = staging.appendingPathComponent(app.lastPathComponent)
        try fm.copyItem(at: app, to: staged)
        return staged
    }

    /// Never swap in something unexamined: a wrong or truncated image would otherwise
    /// replace a working app with one that cannot launch, and there is no way back from
    /// inside an app that will not start.
    private static func check(_ staged: URL, isNewerThan destination: URL) throws {
        let info = staged.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: info),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil
              ) as? [String: Any],
              let identifier = plist["CFBundleIdentifier"] as? String,
              let version = plist["CFBundleShortVersionString"] as? String,
              let executable = plist["CFBundleExecutable"] as? String
        else { throw Failure.unreadableBundle }

        guard identifier == Bundle.main.bundleIdentifier else { throw Failure.wrongApp }
        guard FileManager.default.isExecutableFile(
            atPath: staged.appendingPathComponent("Contents/MacOS/\(executable)").path
        ) else { throw Failure.unreadableBundle }

        let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard Updater.isNewer(version, than: installed) else { throw Failure.notNewer(version) }
    }

    /// Stand down, and have something outside this process start the new copy.
    ///
    /// Asking `NSWorkspace` to open the bundle *this process is running from* — a bundle
    /// whose contents were replaced a moment ago — is the one case that hangs: the call
    /// never returns, so the terminate after it never runs, and an update that installed
    /// perfectly sits on "Reopening the new version…" forever. Which is a bad way for
    /// something whose whole job is to be unattended to fail.
    ///
    /// So nothing here waits on LaunchServices. A detached shell outlives this process,
    /// watches for the pid to go, and only then opens the new copy — by which point there
    /// is no second instance to negotiate and no replaced bundle still in use.
    private static func relaunch(_ bundle: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /usr/bin/open -n \(shellQuoted(bundle.path))
        """
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", script]
        try waiter.run()

        NSApp.terminate(nil)

        // If something refuses the quit, the waiter is left watching a pid that never
        // goes and the update is installed but not running. Past the point of no return
        // — the bundle on disk is already the new one — staying alive on code that no
        // longer exists is the worse outcome of the two.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            exit(0)
        }
    }

    /// The app's path has spaces in it, and this goes through `sh`.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.tool(
                (tool as NSString).lastPathComponent,
                String(data: output, encoding: .utf8) ?? ""
            )
        }
        return String(data: output, encoding: .utf8) ?? ""
    }

    // MARK: - Failures

    private enum Failure: LocalizedError {
        case http(Int)
        case badResponse
        case noAsset
        case noAppInDisk
        case notABundle
        case runningFromDisk
        case notWritable(String)
        case unreadableBundle
        case wrongApp
        case notNewer(String)
        case tool(String, String)

        var errorDescription: String? {
            switch self {
            case .http(403):
                "GitHub is rate-limiting update checks. Try again in a little while."
            case .http(404):
                "No releases have been published yet."
            case .http(let code):
                "GitHub returned \(code)."
            case .badResponse:
                "Could not read GitHub's release information."
            case .noAsset:
                "That release has no Mac build attached to it."
            case .noAppInDisk:
                "The downloaded disk image had no app inside it."
            case .notABundle:
                "This copy is not running as an app bundle, so there is nothing to replace."
            case .runningFromDisk:
                "Drag the app to your Applications folder first — a copy running from a disk image cannot update itself."
            case .notWritable(let path):
                "No permission to replace the app in \(path)."
            case .unreadableBundle:
                "The downloaded app could not be read, so it was discarded."
            case .wrongApp:
                "The downloaded app is a different app, so it was discarded."
            case .notNewer(let version):
                "The download turned out to be \(version), which is not newer."
            case .tool(let name, let detail):
                detail.isEmpty ? "\(name) failed." : "\(name): \(detail.prefix(200))"
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let known = error as? Failure { return known.errorDescription ?? "Update failed." }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "No internet connection."
        }
        return error.localizedDescription
    }
}
