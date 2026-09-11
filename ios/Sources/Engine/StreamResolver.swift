import CoreGraphics
import Foundation

/// Turning a video id into something playable or downloadable.
///
/// This is the part that replaces `yt-dlp -f …` and `-g`. It walks
/// `InnerTube.playerLadder`, asking each client for the video's `streamingData` and
/// keeping the first answer that yields streams, which is the same give-up-capability
/// strategy as the Mac app's rungs.
///
/// ## Where the bot wall sits
///
/// The `player` endpoint is gated far harder than the listing endpoints this app also
/// uses. On 2026-09-11, from a datacenter address, **every** client in the ladder came
/// back `LOGIN_REQUIRED` / "Sign in to confirm you're not a bot" with zero formats,
/// while `browse` and `search` answered normally from the same address. So a failure
/// here is usually about *where the request came from*, not about the code.
///
/// Residential and cellular addresses — which is what an iPhone running this app is —
/// are treated much more leniently, so this is expected to behave differently on a real
/// device than it does from a server. That asymmetry is why the listing half of the app
/// could be verified end to end here and this half could not; see ios/README.md.
///
/// If the wall does follow you onto the device, the remedy YouTube is asking for is a
/// signed-in session or a PO token, neither of which this app has. `Failure.refused`
/// carries YouTube's own wording through to the UI so the reason is at least visible.
enum StreamResolver {

    // MARK: - What comes back

    /// One media stream YouTube is offering.
    struct Stream: Sendable {
        let itag: Int
        let url: URL
        let mimeType: String
        let bitrate: Int
        let width: Int?
        let height: Int?
        let contentLength: Int64?

        /// `video/mp4; codecs="avc1.640028"` -> "avc1.640028".
        var codec: String {
            guard let range = mimeType.range(of: "codecs=") else { return "" }
            return mimeType[range.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }

        var isVideo: Bool { mimeType.hasPrefix("video/") }
        var isAudio: Bool { mimeType.hasPrefix("audio/") }

        /// Whether AVFoundation can carry this stream into an `.mp4` untouched.
        ///
        /// This is the constraint that shapes the whole of `pick` below, and the one a
        /// naive port of the Mac's format selectors would miss. On the Mac, yt-dlp hands
        /// whatever it likes to a vendored ffmpeg, which re-containerises anything. iOS
        /// has no ffmpeg here — `Muxer` uses `AVAssetExportSession` passthrough — and
        /// AVFoundation will not write VP9, AV1 or Opus into an MP4. So YouTube's
        /// highest-efficiency formats, which are usually its *best* formats, are simply
        /// not available to this app, and asking for them produces an export that fails
        /// at the very end of a long download.
        ///
        /// H.264 tops out at 1080p on YouTube, which is why `Quality.best` cannot mean
        /// 4K here the way it does on the Mac.
        var isMuxable: Bool {
            if isVideo { return codec.hasPrefix("avc1") || codec.hasPrefix("hvc1") || codec.hasPrefix("hev1") }
            if isAudio { return codec.hasPrefix("mp4a") }
            return false
        }

        var fileExtension: String { isAudio ? "m4a" : "mp4" }
    }

    /// A resolved video: either one HLS URL, or the streams to fetch and stitch.
    struct Resolved: Sendable {
        enum Source: Sendable {
            /// A master playlist. AVPlayer handles this end to end — every rendition and
            /// the audio in one URL, adaptive and seekable. Playback's preferred answer.
            case hls(URL)
            /// Separate streams, which is what a download always needs and what playback
            /// falls back to.
            case pair(video: Stream, audio: Stream?)
            /// Audio with no video, for audio-only downloads.
            case audioOnly(Stream)
        }

        let source: Source
        let title: String
        let duration: Int?
        let aspectRatio: CGFloat?
        /// Which client answered, for the log and for the error message.
        let client: String

        /// Combined bytes, when YouTube said. Drives the download's progress bar, which
        /// otherwise cannot show a total across two files.
        var expectedBytes: Int64? {
            switch source {
            case .hls: nil
            case .pair(let video, let audio):
                video.contentLength.map { $0 + (audio?.contentLength ?? 0) }
            case .audioOnly(let audio): audio.contentLength
            }
        }
    }

    /// What the caller wants, which changes which rung is acceptable.
    enum Purpose: Sendable {
        /// Prefers HLS and is happy with any quality — it is a look, not a keep.
        case playback
        /// Needs separate streams at a specific quality, muxable ones only.
        case download(Quality)
    }

    // MARK: - Resolving

    static func resolve(videoID: String, for purpose: Purpose) async throws -> Resolved {
        var lastError: Error?

        for client in InnerTube.playerLadder {
            do {
                let response = try await InnerTube.post(
                    "player",
                    client: client,
                    payload: [
                        "videoId": videoID,
                        "contentCheckOk": true,
                        "racyCheckOk": true,
                    ]
                )
                try check(playability: response)

                if let resolved = try await build(
                    from: response, client: client, purpose: purpose, videoID: videoID
                ) {
                    Log.engine.info(
                        "resolved \(videoID, privacy: .public) via \(client.key, privacy: .public)")
                    return resolved
                }
            } catch {
                Log.engine.info(
                    "\(client.key, privacy: .public) failed \(videoID, privacy: .public): "
                        + "\(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }

        throw lastError ?? Failure.noStreams
    }

    /// InnerTube reports refusals inside a 200 response.
    private static func check(playability response: [String: Any]) throws {
        guard let status = response["playabilityStatus"] as? [String: Any],
              let state = status["status"] as? String
        else { return }
        switch state {
        case "OK": return
        case "LOGIN_REQUIRED":
            throw Failure.refused("This video needs a signed-in account "
                + "(it is private, members-only, or age-restricted).")
        case "LIVE_STREAM_OFFLINE":
            throw Failure.refused("That stream has not started.")
        default:
            let reason = Renderers.text(status["reason"])
                ?? (status["reason"] as? String)
                ?? state
            throw Failure.refused(reason)
        }
    }

    private static func build(
        from response: [String: Any],
        client: InnerTube.Client,
        purpose: Purpose,
        videoID: String
    ) async throws -> Resolved? {
        let details = response["videoDetails"] as? [String: Any] ?? [:]
        let title = (details["title"] as? String) ?? videoID
        let duration = (details["lengthSeconds"] as? String).flatMap(Int.init)
        let streaming = response["streamingData"] as? [String: Any] ?? [:]

        // HLS first for playback: one URL, no descrambling, no muxing, and AVPlayer
        // does the adaptive switching itself.
        if case .playback = purpose,
           let manifest = streaming["hlsManifestUrl"] as? String,
           let url = URL(string: manifest) {
            return Resolved(source: .hls(url), title: title, duration: duration,
                            aspectRatio: nil, client: client.key)
        }

        let raw = (streaming["adaptiveFormats"] as? [[String: Any]] ?? [])
            + (streaming["formats"] as? [[String: Any]] ?? [])
        guard !raw.isEmpty else { return nil }

        // Descrambling is per-format and only the web client needs it, so the solver is
        // fetched once here rather than per stream.
        let solver: JSSolver? = client.needsDescrambling
            ? try? await JSChallenge.shared.solver()
            : nil
        let streams = raw.compactMap { stream(from: $0, solver: solver) }
        guard !streams.isEmpty else { return nil }

        guard let source = pick(from: streams, for: purpose) else { return nil }

        var ratio: CGFloat?
        if case .pair(let video, _) = source,
           let width = video.width, let height = video.height, height > 0 {
            ratio = CGFloat(width) / CGFloat(height)
        }
        return Resolved(source: source, title: title, duration: duration,
                        aspectRatio: ratio, client: client.key)
    }

    // MARK: - Choosing

    /// Pick the streams to use.
    ///
    /// Muxable formats only, always — see `Stream.isMuxable`. Within those: the tallest
    /// video at or below the cap, and the best audio, which for playback and for every
    /// download is the same choice because YouTube only offers two or three AAC rungs.
    private static func pick(from streams: [Stream], for purpose: Purpose) -> Resolved.Source? {
        let muxable = streams.filter(\.isMuxable)
        let audio = muxable.filter(\.isAudio).max { $0.bitrate < $1.bitrate }

        let cap: Int?
        switch purpose {
        case .playback:
            // A phone screen is not worth 1080p over cellular, and the stitched
            // fallback has to index both remote files before playing — smaller is
            // noticeably faster to first frame.
            cap = 720
        case .download(let quality):
            if quality.isAudioOnly {
                guard let audio else { return nil }
                return .audioOnly(audio)
            }
            cap = quality.heightCap
        }

        let videos = muxable.filter(\.isVideo)
        let eligible = cap.map { limit in videos.filter { ($0.height ?? 0) <= limit } } ?? videos
        // If the cap excluded everything, take the shortest available rather than
        // failing: a video whose only H.264 rendition is 1080p should still play when
        // 720p was asked for.
        let chosen = (eligible.isEmpty ? videos : eligible)
            .max { ($0.height ?? 0, $0.bitrate) < ($1.height ?? 0, $1.bitrate) }

        guard let chosen else {
            // No muxable video at all. Audio alone still beats nothing for playback.
            return audio.map { .audioOnly($0) }
        }
        return .pair(video: chosen, audio: audio)
    }

    // MARK: - Decoding one format

    private static func stream(from json: [String: Any], solver: JSSolver?) -> Stream? {
        guard let itag = json["itag"] as? Int,
              let mimeType = json["mimeType"] as? String
        else { return nil }

        guard let url = url(from: json, solver: solver) else { return nil }

        return Stream(
            itag: itag,
            url: url,
            mimeType: mimeType,
            bitrate: (json["bitrate"] as? Int) ?? 0,
            width: json["width"] as? Int,
            height: json["height"] as? Int,
            // `contentLength` is a string in the JSON, not a number.
            contentLength: (json["contentLength"] as? String).flatMap(Int64.init)
        )
    }

    /// The playable URL for one format, descrambled if it needs to be.
    ///
    /// Two separate obfuscations, and they are not alternatives — a web-client format
    /// usually has both:
    ///
    /// - `signatureCipher` holds the URL with its signature scrambled. Without
    ///   unscrambling it the request 403s.
    /// - `n` is a throttling parameter present on every URL. Leaving it alone does not
    ///   fail the request; it succeeds and then serves at roughly 50 KB/s, which is the
    ///   symptom to recognise when the solver has quietly stopped working.
    private static func url(from json: [String: Any], solver: JSSolver?) -> URL? {
        var raw: String

        if let plain = json["url"] as? String {
            raw = plain
        } else if let cipher = json["signatureCipher"] as? String ?? json["cipher"] as? String {
            let fields = query(cipher)
            guard let base = fields["url"] else { return nil }
            guard let scrambled = fields["s"], let solver,
                  let signature = solver.signature(scrambled)
            else { return nil }
            let parameter = fields["sp"] ?? "signature"
            raw = base + (base.contains("?") ? "&" : "?") + parameter + "="
                + (signature.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? signature)
        } else {
            return nil
        }

        if let solver, let components = URLComponents(string: raw),
           let items = components.queryItems,
           let n = items.first(where: { $0.name == "n" })?.value,
           let transformed = solver.transformN(n) {
            var rebuilt = components
            rebuilt.queryItems = items.map {
                $0.name == "n" ? URLQueryItem(name: "n", value: transformed) : $0
            }
            return rebuilt.url ?? URL(string: raw)
        }
        return URL(string: raw)
    }

    /// Parse a urlencoded body into a dictionary. `URLComponents` is not usable here:
    /// the value of `url` is itself a full percent-encoded URL with its own query.
    private static func query(_ body: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            guard let split = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[pair.startIndex..<split])
            let value = String(pair[pair.index(after: split)...])
            fields[key] = value.removingPercentEncoding ?? value
        }
        return fields
    }

    // MARK: - Failures

    enum Failure: LocalizedError {
        case noStreams
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .noStreams:
                "No playable stream came back for this video. It may be region-locked, "
                    + "or only offered in a format this app cannot handle."
            case .refused(let reason):
                reason
            }
        }
    }
}
