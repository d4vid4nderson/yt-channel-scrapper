import Foundation

/// Keeps yt-dlp current.
///
/// YouTube breaks yt-dlp every few weeks, so a version fixed at build time quietly ages
/// out of working. The copy inside the bundle cannot be replaced — the bundle is signed
/// and read-only — so an update is downloaded beside it in Application Support and
/// preferred from then on, the same overlay trick the Flask app used for its wheel.
///
/// Unlike that version, this one takes effect immediately: every scrape and download
/// spawns a fresh yt-dlp process, so the next one simply picks up the new binary. There
/// is nothing to restart.
@MainActor
@Observable
final class Updater {
    enum State: Equatable {
        case unknown
        case checking
        case upToDate
        case available(String)
        case downloading(Double)      // 0...1
        case installing
        case installed(String)
        case failed(String)
    }

    private(set) var state: State = .unknown
    private(set) var current = ""

    private var assetURL: URL?
    private var latest: String?

    private static let releaseAPI = URL(
        string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
    )!
    private static let assetName = "yt-dlp_macos"

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    var canInstall: Bool {
        if case .available = state { return true }
        return false
    }

    // MARK: - Reading the current version

    func refreshCurrent() async {
        if let version = await version(of: Paths.ytdlp) {
            current = version
        }
    }

    // MARK: - Checking

    func check() async {
        guard !isBusy else { return }
        state = .checking
        if current.isEmpty { await refreshCurrent() }

        do {
            var request = URLRequest(url: Self.releaseAPI)
            // GitHub answers unauthenticated requests but wants to know who is asking.
            request.setValue("YT-Channel-Scraper", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw Failure.http(code)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]]
            else { throw Failure.badResponse }

            guard let asset = assets.first(where: { $0["name"] as? String == Self.assetName }),
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString)
            else { throw Failure.noAsset }

            latest = tag
            assetURL = url
            state = Self.isNewer(tag, than: current) ? .available(tag) : .upToDate
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    // MARK: - Installing

    func install() async {
        guard case .available = state, let source = assetURL else { return }
        state = .downloading(0)

        do {
            let watcher = DownloadWatcher { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(fraction)
                }
            }

            var request = URLRequest(url: source)
            request.setValue("YT-Channel-Scraper", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 300

            let (tempURL, response) = try await URLSession.shared.download(
                for: request, delegate: watcher
            )
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0)
            }

            state = .installing

            let fm = FileManager.default
            // Stage it next to its destination so the final move cannot cross volumes.
            let binDir = Paths.ytdlpOverride.deletingLastPathComponent()
            try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
            let staged = binDir.appendingPathComponent("yt-dlp_macos.incoming")
            if fm.fileExists(atPath: staged.path) { try fm.removeItem(at: staged) }
            try fm.moveItem(at: tempURL, to: staged)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)

            // Never put a binary live without seeing it run: a truncated or wrong-arch
            // download would otherwise break every scrape with no way back through the UI.
            guard let reported = await version(of: staged) else {
                try? fm.removeItem(at: staged)
                throw Failure.didNotRun
            }

            if fm.fileExists(atPath: Paths.ytdlpOverride.path) {
                try fm.removeItem(at: Paths.ytdlpOverride)
            }
            try fm.moveItem(at: staged, to: Paths.ytdlpOverride)

            current = reported
            state = .installed(reported)
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// Drop back to the copy inside the bundle.
    func revertToBundled() async {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Paths.ytdlpOverride.path) else { return }
        try? fm.removeItem(at: Paths.ytdlpOverride)
        await refreshCurrent()
        state = .unknown
    }

    var isUsingDownloadedCopy: Bool {
        FileManager.default.isExecutableFile(atPath: Paths.ytdlpOverride.path)
    }

    // MARK: - Helpers

    private func version(of binary: URL) async -> String? {
        let stream = ProcessStream(
            executable: binary,
            arguments: ["--version"],
            environment: YtDlp.environment
        )
        var output = ""
        do {
            for try await line in stream.lines() { output += line }
        } catch {
            return nil
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// yt-dlp versions are dates — 2026.08.19, sometimes with a fourth component for a
    /// same-day re-release — so they compare component-wise as numbers, not as strings.
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard !installed.isEmpty else { return true }
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = installed.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private enum Failure: LocalizedError {
        case http(Int)
        case badResponse
        case noAsset
        case didNotRun

        var errorDescription: String? {
            switch self {
            case .http(let code) where code == 403:
                "GitHub is rate-limiting update checks. Try again in a little while."
            case .http(let code):
                "GitHub returned \(code)."
            case .badResponse:
                "Could not read GitHub's release information."
            case .noAsset:
                "That release has no macOS build."
            case .didNotRun:
                "The downloaded copy would not run, so it was discarded."
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

/// Reports download progress; `URLSession`'s async `download` gives none on its own.
private final class DownloadWatcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    // Required by the protocol; the async download API takes the file from its own return.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}
