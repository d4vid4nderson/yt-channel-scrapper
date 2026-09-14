import Foundation

/// YouTube's own private API, which is what replaces yt-dlp on iOS.
///
/// The Mac app shells out to yt-dlp for everything. iOS has no `Process` — the class is
/// not in the SDK, and the sandbox would refuse to exec a vendored binary even if it
/// were — so the extraction has to happen in-process. This is that: the same InnerTube
/// endpoints yt-dlp itself talks to, called directly.
///
/// ## What rots
///
/// Everything in `Client` below is a moving target. YouTube rotates client versions,
/// withdraws clients, and adds PO-token requirements to them one at a time. When
/// extraction starts failing, the fix is almost always a new version string here rather
/// than new logic — cross-check against yt-dlp's `INNERTUBE_CLIENTS` in
/// `yt_dlp/extractor/youtube/_base.py`, which is kept current by people watching this
/// full-time.
enum InnerTube {
    static let host = URL(string: "https://www.youtube.com")!
    static let base = URL(string: "https://www.youtube.com/youtubei/v1/")!

    /// One InnerTube client identity.
    ///
    /// Which one you claim to be changes what comes back, and by how much: the mobile
    /// clients hand over stream URLs that need no descrambling, the web client hands
    /// over URLs whose signature has to be run through the player's own JavaScript
    /// first. So the app claims to be a mobile client where it can and only falls back
    /// to the web one, with the solver behind it, when it must.
    struct Client: Sendable {
        let key: String
        /// `clientName` in the context, and the `X-YouTube-Client-Name` header takes the
        /// matching numeric id.
        let name: String
        let numericID: Int
        let version: String
        let userAgent: String
        /// Merged into `context.client`. Device fields the mobile clients expect.
        let extraContext: [String: String]
        /// Whether `streamingData` comes back with playable URLs as-is. When false the
        /// formats carry a `signatureCipher` and an `n` parameter that have to go
        /// through `JSChallenge` before anything will stream.
        let needsDescrambling: Bool
        /// Whether this client is served an HLS master playlist. That is the good path
        /// on iOS: one URL carrying every rendition plus audio, which AVPlayer plays
        /// natively — no descrambling, no muxing, no format picking.
        let servesHLS: Bool

        /// The `context.client` dictionary for a request.
        var context: [String: String] {
            var fields = [
                "clientName": name,
                "clientVersion": version,
                "hl": "en",
                "gl": "US",
            ]
            fields.merge(extraContext) { _, new in new }
            return fields
        }
    }

    // MARK: - The clients

    /// The Vision Pro's YouTube app, and currently the best rung on the ladder.
    ///
    /// It is outside the proof-of-origin requirement, needs no JavaScript player, and —
    /// unlike `android_vr`, the other client with those properties — is served the whole
    /// H.264 ladder up to 1080p with AAC beside it, which is exactly the pair `Muxer`
    /// can write through without re-encoding. Verified against a live video on
    /// 2026-09-13: formats 137 (1920x1080 avc1) and 140 (m4a) both offered, no PO token.
    static let visionOSClient = Client(
        key: "visionos",
        name: "VISIONOS",
        numericID: 101,
        version: "1.02",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/26.0 Safari/605.1.15",
        extraContext: [
            "deviceMake": "Apple",
            "deviceModel": "RealityDevice17,1",
            "osName": "visionOS",
            "osVersion": "26.5.23O471",
        ],
        needsDescrambling: false,
        servesHLS: true
    )

    /// The iOS YouTube app.
    ///
    /// It used to lead the ladder, because it is the one client that reliably hands back
    /// an `hlsManifestUrl`. It no longer earns that place: as of yt-dlp 2026.08.19 its
    /// media URLs carry `GvsPoTokenPolicy(required: true)`, meaning YouTube serves the
    /// URL and then answers the fetch with 403 unless a proof-of-origin token rides
    /// along. This app has no way to mint one, so the rung resolves, promises an HLS
    /// master, and fails the moment anything reads from it.
    static let iosClient = Client(
        key: "ios",
        name: "IOS",
        numericID: 5,
        version: "21.02.3",
        userAgent: "com.google.ios.youtube/21.02.3 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        extraContext: [
            "deviceMake": "Apple",
            "deviceModel": "iPhone16,2",
            "osName": "iPhone",
            "osVersion": "18.3.2.22D82",
        ],
        needsDescrambling: false,
        servesHLS: true
    )

    /// The Quest's YouTube app. Unglamorous, and the most durable of the lot: it has
    /// stayed outside the PO-token requirement longest and returns plain URLs.
    static let androidVRClient = Client(
        key: "android_vr",
        name: "ANDROID_VR",
        numericID: 28,
        version: "1.65.10",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; "
            + "eureka-user Build/SQ3A.220605.009.A1) gzip",
        extraContext: [
            "deviceMake": "Oculus",
            "deviceModel": "Quest 3",
            "osName": "Android",
            "osVersion": "12L",
            "androidSdkVersion": "32",
        ],
        needsDescrambling: false,
        servesHLS: false
    )

    /// The TV client. Another no-descrambling route, and the usual answer for videos the
    /// mobile clients refuse.
    static let tvClient = Client(
        key: "tv",
        name: "TVHTML5",
        numericID: 7,
        version: "7.20260114.12.00",
        userAgent: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold "
            + "(unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)",
        extraContext: [:],
        needsDescrambling: false,
        servesHLS: false
    )

    /// The desktop site. Always answers, and always makes you work for it — this is the
    /// rung that needs `JSChallenge`. Also the only client whose *browse* and *search*
    /// responses have the shapes `Renderers` knows how to read, so listing always uses
    /// it regardless of which client resolves the streams.
    static let webClient = Client(
        key: "web",
        name: "WEB",
        numericID: 1,
        version: "2.20250312.04.00",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
        extraContext: [:],
        needsDescrambling: true,
        servesHLS: false
    )

    /// The order `StreamResolver` walks, and the direct analogue of `YtDlp.ladder` on
    /// the Mac: give up capability rung by rung rather than retrying the same thing.
    /// HLS first because it is the cheapest good answer, then the two plain-URL clients,
    /// then the web client with the solver behind it as the one that always answers.
    static let playerLadder: [Client] = [
        visionOSClient,     // no PO token, no JS, full H.264 ladder — the one that works
        androidVRClient,    // no PO token either, but usually only the muxed 360p rung
        tvClient,
        iosClient,          // PO-token gated: resolves, then 403s. Kept for HLS if it lifts
        webClient,          // needs JSChallenge, which does not currently solve
    ]

    // MARK: - Requests

    struct Failure: LocalizedError {
        let endpoint: String
        let status: Int
        let detail: String?

        var errorDescription: String? {
            if let detail, !detail.isEmpty { return detail }
            return "YouTube returned \(status) for \(endpoint)."
        }
    }

    /// One session for the whole app, so YouTube's cookies (`VISITOR_INFO1_LIVE` and
    /// friends) persist across calls. Without a stable visitor the listing endpoints
    /// start returning empty continuations after a few pages.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// POST a JSON body to one of the `youtubei/v1` endpoints and hand back the parsed
    /// object. `payload` is merged over the standard context, so a caller only supplies
    /// what is specific to its call (`videoId`, `browseId`, `continuation`, …).
    static func post(
        _ endpoint: String,
        client: Client,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        var body: [String: Any] = [
            "context": [
                "client": client.context,
                "user": ["lockedSafetyMode": false],
                "request": ["useSsl": true],
            ],
        ]
        body.merge(payload) { _, new in new }

        // The one field that decides whether `player` answers at all. Without it every
        // client comes back LOGIN_REQUIRED / "Sign in to confirm you're not a bot" with
        // zero formats, which reads like an IP-based block and is not one: it fails the
        // same way from a phone on cellular as from a datacenter, and supplying this
        // fixes it from either. Measured 2026-09-13 — see ios/README.md.
        if let visitor = await VisitorID.shared.get(),
           var context = body["context"] as? [String: Any],
           var fields = context["client"] as? [String: String] {
            fields["visitorData"] = visitor
            context["client"] = fields
            body["context"] = context
        }

        var request = URLRequest(url: base.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        // The numeric id, not the name. `numericID` was carried on every client and
        // never read, so this header has always said "WEB" where YouTube wanted "1".
        request.setValue(String(client.numericID), forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let visitor = await VisitorID.shared.get() {
            request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure(endpoint: endpoint, status: status,
                          detail: Self.errorText(in: data))
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(endpoint: endpoint, status: status, detail: "Unreadable response.")
        }
        return object
    }

    /// Fetch a plain page — the watch page, for the player script URL.
    static func get(_ url: URL, client: Client) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure(endpoint: url.path, status: status, detail: nil)
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// InnerTube reports its own failures inside a 200, so a status check alone is not
    /// enough; this digs out the message when there is one to show.
    private static func errorText(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }
}
