import Foundation

/// Builds yt-dlp invocations. Nothing here runs anything; `ProcessStream` does that.
enum YtDlp {
    /// Sentinels that let one stdout stream carry two kinds of line.
    static let progressPrefix = "PROG\u{1F}"
    static let finalPrefix = "FINAL\u{1F}"

    /// yt-dlp finds Deno by bare name through PATH, and an app launched from Finder
    /// inherits a minimal PATH with no Homebrew in it — so vendor/ has to go on the
    /// front or the JS challenge solver silently is not there.
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Paths.vendor.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }

    /// Point a bare channel URL at one of its tabs; leave playlists alone.
    /// Port of `normalize_channel_url`.
    static func channelURL(from raw: String, path: String) throws -> String {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { throw Failure.noURL }
        if !url.hasPrefix("http") {
            url = "https://www.youtube.com/" + url.drop(while: { $0 == "/" })
        }
        if url.contains("list=") || url.contains("/playlist") { return url }
        url = url.replacing(
            /\/(videos|shorts|streams|releases|playlists|podcasts|featured)\/?$/,
            with: ""
        )
        while url.hasSuffix("/") { url.removeLast() }
        return "\(url)/\(path)"
    }

    enum Failure: LocalizedError {
        case noURL
        case noTab(String)

        var errorDescription: String? {
            switch self {
            case .noURL:
                "No URL provided"
            case .noTab(let label):
                "No \(label) found for that channel — it may not have a \(label) tab. "
                    + "Check the URL, or try a different type."
            }
        }
    }

    // MARK: - Scraping

    /// List one page of a channel tab. `--lazy-playlist` is what makes the first results
    /// arrive in seconds rather than after the whole channel has been walked.
    static func scrapeArguments(url: String, offset: Int, count: Int) -> [String] {
        [
            "--ignore-config", "--flat-playlist", "--dump-json",
            "--no-warnings", "--ignore-errors", "--lazy-playlist",
            "--playlist-items", "\(offset + 1):\(offset + count)",
            url,
        ]
    }

    // MARK: - Downloading

    /// The rungs a download steps down through, in order.
    ///
    /// A plain extraction now 403s on every format above 360p: YouTube gates those
    /// behind both a solved JS challenge and a signed-in session. Retrying identical
    /// options cannot clear either, so the attempts give up capability instead —
    /// cookies + solver, then solver alone, then the android client, which needs
    /// neither but caps out at 360p. The last rung always downloads something.
    struct Rung {
        let name: String
        let arguments: [String]
        /// A browser holding no YouTube cookies fails instantly and costs nothing, so
        /// only the rungs that actually talked to YouTube are worth backing off after.
        var backsOff: Bool { name != "cookies" }
    }

    static let cookieBrowsers = ["chrome", "brave", "edge", "firefox", "safari"]

    static var ladder: [Rung] {
        var rungs: [Rung] = []
        if Paths.hasJSRuntime {
            for browser in cookieBrowsers {
                rungs.append(Rung(
                    name: "cookies",
                    arguments: ["--remote-components", "ejs:github",
                                "--cookies-from-browser", browser]
                ))
            }
            rungs.append(Rung(name: "solver", arguments: ["--remote-components", "ejs:github"]))
        }
        rungs.append(Rung(
            name: "android",
            arguments: ["--extractor-args", "youtube:player_client=android"]
        ))
        return rungs
    }

    static func downloadArguments(video: Video, quality: Quality, rung: Rung) -> [String] {
        var args = [
            "--ignore-config", "--newline", "--no-warnings", "--no-playlist",
            "--restrict-filenames",
            "--retries", "5", "--fragment-retries", "5", "--extractor-retries", "3",
            "-f", quality.formatSelector,
            "-o", Paths.downloads.appendingPathComponent("%(title).150B [%(id)s].%(ext)s").path,
            "--progress-template",
            progressPrefix + "%(progress.status)s\u{1F}%(progress.downloaded_bytes)s"
                + "\u{1F}%(progress.total_bytes)s\u{1F}%(progress.total_bytes_estimate)s"
                + "\u{1F}%(progress.speed)s\u{1F}%(progress.eta)s\u{1F}%(progress.filename)s",
            "--print", "after_move:" + finalPrefix + "%(filepath)s",
        ]
        if Paths.hasFFmpeg {
            args += ["--ffmpeg-location", Paths.vendor.path]
        }
        if quality.isAudioOnly {
            args += ["-x", "--audio-format", "mp3", "--audio-quality", "192K"]
        } else {
            args += ["--merge-output-format", "mp4"]
        }
        args += rung.arguments
        args.append(video.url.absoluteString)
        return args
    }

    // MARK: - Preview

    /// Ask for YouTube's own HLS master playlist, plus the frame size.
    ///
    /// This is the preferred preview source: one URL carrying every quality *and* the
    /// audio, which AVPlayer plays natively — adaptive, seekable, and correct for an
    /// hour-long video. Stitching the separate streams together instead forces
    /// AVFoundation to index the whole remote file, which never finishes on long ones.
    /// The rungs a *preview* tries, and only these.
    ///
    /// A preview must feel immediate, and the download ladder cannot: its five
    /// `--cookies-from-browser` rungs each cost a full extraction, which measured at
    /// ~44s before reaching the one that worked. They buy nothing here either — 720p
    /// HLS is not gated, and an ad-hoc-signed app cannot decrypt Chrome's cookie
    /// keychain regardless. The solver rung is what answers; android is the backstop.
    static var previewLadder: [Rung] {
        var rungs: [Rung] = []
        if Paths.hasJSRuntime {
            rungs.append(Rung(name: "solver", arguments: ["--remote-components", "ejs:github"]))
        }
        rungs.append(Rung(
            name: "android",
            arguments: ["--extractor-args", "youtube:player_client=android"]
        ))
        return rungs
    }

    /// No height cap on the selector: every format reports the *same* master playlist,
    /// which carries every variant up to 1080p, so a cap would not limit playback — it
    /// would only mis-report the aspect ratio, and would fail outright on a video whose
    /// variants all sit above it.
    static func manifestArguments(video: Video, rung: Rung) -> [String] {
        ["--ignore-config", "--no-warnings", "--no-playlist",
         "--print", "%(manifest_url)s|%(width)s|%(height)s",
         "-f", "bv*[protocol^=m3u8]"]
            + rung.arguments
            + [video.url.absoluteString]
    }

    /// Resolve playable stream URLs without downloading anything.
    ///
    /// `-g` prints one URL per line: two when video and audio are separate, which for
    /// YouTube is now always — progressive formats are gone. Capped at 720p, since this
    /// is a look before committing to a download, not the download itself.
    static func streamArguments(video: Video, rung: Rung) -> [String] {
        ["--ignore-config", "--no-warnings", "--no-playlist", "-g",
         "-f", "bv[ext=mp4][height<=?720]+ba[ext=m4a]/b[height<=?720]/b"]
            + rung.arguments
            + [video.url.absoluteString]
    }

    /// Learn the combined size of the streams a download will fetch.
    ///
    /// A merged download runs two passes, each reporting 0-100% of its own file; without
    /// a combined total the first stream alone would read as 100%.
    static func probeArguments(video: Video, quality: Quality, rung: Rung) -> [String] {
        ["--ignore-config", "--no-warnings", "--no-playlist", "--dump-json", "--no-download",
         "-f", quality.formatSelector]
            + rung.arguments
            + [video.url.absoluteString]
    }
}
