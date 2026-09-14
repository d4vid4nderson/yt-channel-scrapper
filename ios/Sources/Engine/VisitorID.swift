import Foundation

/// YouTube's anonymous visitor id, fetched once and kept for the life of the process.
///
/// This is the difference between the `player` endpoint answering and refusing. Without
/// a `visitorData` the response is `LOGIN_REQUIRED` with the reason "Sign in to confirm
/// you're not a bot" and no formats at all — for every client in the ladder, from any
/// address. It looks exactly like an IP reputation block, which is what it was taken for
/// until the same request was replayed twice, once with this field and once without:
///
///     no visitorData  -> LOGIN_REQUIRED, 0 formats
///     visitorData     -> OK, 23 adaptive formats, HLS offered
///
/// The value is whatever `ytcfg` on any YouTube page carries. One fetch per launch is
/// enough, and concurrent callers share it rather than each pulling their own — several
/// arrive together, because the ladder and the listing both start at once.
actor VisitorID {
    static let shared = VisitorID()

    private var cached: String?
    private var inFlight: Task<String?, Never>?

    func get() async -> String? {
        if let cached { return cached }
        if let inFlight { return await inFlight.value }

        let task = Task { await Self.fetch() }
        inFlight = task
        let value = await task.value
        inFlight = nil
        // A failure is not cached: the next call should be free to try again, and the
        // app degrades to exactly the behaviour it had before this existed.
        if let value { cached = value }
        return value
    }

    private static func fetch() async -> String? {
        guard let url = URL(string: "https://www.youtube.com/") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(InnerTube.webClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        guard let (data, _) = try? await InnerTube.session.data(for: request),
              let html = String(data: data, encoding: .utf8)
        else {
            Log.engine.error("visitor id: could not read youtube.com")
            return nil
        }

        guard let value = extract(from: html) else {
            Log.engine.error("visitor id: no visitorData in ytcfg")
            return nil
        }
        Log.engine.info("visitor id acquired")
        return value
    }

    /// Pull `"visitorData":"…"` out of the page.
    ///
    /// Decoded as JSON rather than read literally: the value is base64 and routinely
    /// carries `=` for its `=` padding, which would otherwise be sent through
    /// verbatim and rejected.
    static func extract(from html: String) -> String? {
        guard let range = html.range(of: "\"visitorData\":\"") else { return nil }
        let rest = html[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let raw = String(rest[rest.startIndex..<end])
        guard let data = "\"\(raw)\"".data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data)
        else { return raw }
        return decoded
    }
}
