import Foundation

/// Fetching one stream to a file, with progress.
///
/// A **background** `URLSession`, which is the point: a 1080p video is minutes of
/// transfer, and a foreground session stops the moment the user switches apps. A
/// background session is handed to the system, which keeps going while the app is
/// suspended and wakes it when a task finishes — the app just has to be there to be
/// woken, which `YTScraperApp`'s `.backgroundTask(.urlSession:)` handles.
///
/// The one thing a background session cannot survive is the app being *killed*, either
/// by the user or by the system under memory pressure: the continuations below go with
/// the process. A download interrupted that way is reported as failed and can be started
/// again. For the alternative — a fully resumable queue persisted across launches —
/// every job's state would have to live on disk and be reattached by `taskDescription`
/// on the next launch, which is a lot of machinery for a case that is rare on a phone
/// that is not otherwise busy.
actor Transfer {
    static let shared = Transfer()

    /// Must be stable across launches: the system matches a relaunched app to its
    /// outstanding background tasks by this identifier.
    static let sessionIdentifier = "com.d4vid4nderson.ytchannelscraper.transfer"

    private var session: URLSession!
    private let delegate = Delegate()

    init() {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        // These downloads are the user waiting on something they asked for, not
        // housekeeping, so they should not be deferred to a charging window.
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        // A stream URL from YouTube is signed and time-limited; there is no point
        // holding a stalled connection open past the point the URL would expire.
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    /// Download `url` to a file under `Paths.scratch` and hand back where it landed.
    ///
    /// `onProgress` is called with (bytesWritten, totalExpected) as it goes; the total
    /// is -1 when the server did not say.
    /// How much to ask for at a time.
    ///
    /// The single most important number in this file. googlevideo throttles one
    /// long-lived request down to roughly the video's own playback bitrate — measured
    /// 2026-09-13, an open-ended `bytes=0-` held 701 KB/s flat from the first megabyte,
    /// while the same 48 MB fetched as 8 MB ranges came down at 3559 KB/s. Five times
    /// faster for the same bytes off the same URL. It is why yt-dlp has
    /// `--http-chunk-size`, and why this cannot be one request no matter how convenient
    /// that would be.
    private static let chunkSize: Int64 = 8 * 1024 * 1024

    /// Download `url` into `Paths.scratch`, one range at a time.
    ///
    /// Resumption falls out of the design rather than needing `URLSession`'s resume
    /// data: whatever is already on disk is how far we got, so a paused job continues
    /// from its own file length. That survives things resume data does not — notably a
    /// YouTube URL expiring, since the offset is just a number and the next attempt can
    /// carry it to a freshly resolved URL.
    func download(
        _ url: URL,
        named name: String,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        let destination = Paths.scratch.appendingPathComponent(name)
        var have = Self.sizeOnDisk(destination)
        var total: Int64 = -1
        var restarted = false

        while true {
            try Task.checkCancellation()

            let end = have + Self.chunkSize - 1
            // Captured as lets: the closure escapes, and `have`/`total` are moving.
            let base = have
            let known = total
            let chunk: URL
            let response: HTTPURLResponse?
            do {
                (chunk, response) = try await fetchRange(
                    url, "bytes=\(have)-\(end)", into: "\(name).part",
                    reporting: { written in onProgress(base + written, known) })
            } catch Failure.http(416) where have > 0 && !restarted {
                // Range Not Satisfiable: the offset we resumed from is at or past the
                // end of the resource. The file on disk is stale — a different format,
                // or over-long from an earlier append — so it is worth nothing. Throw
                // it away and fetch from the beginning, once.
                let detail = "\(name): stale partial of \(have) bytes, restarting"
                Log.transfer.error("\(detail, privacy: .public)")
                try? FileManager.default.removeItem(at: destination)
                have = 0
                total = -1
                restarted = true
                continue
            }

            if total < 0 { total = Self.totalLength(from: response) ?? -1 }

            let got = Self.sizeOnDisk(chunk)
            guard got > 0 else {
                try? FileManager.default.removeItem(at: chunk)
                break                      // server had nothing more to give
            }
            try Self.append(chunk, to: destination)
            have += got
            onProgress(have, total)

            // A short chunk is only proof of the end when nothing better is known.
            // With a total from Content-Range, trust that instead and ask again from
            // the new offset: a range that comes back short because the connection
            // hiccuped is recoverable, and treating it as the end silently truncates
            // the file — which then downloads "successfully" and will not open.
            if total > 0 {
                if have >= total { break }
            } else if got < Self.chunkSize {
                break
            }
        }

        // Never hand back a file that is shorter than the server said it would be.
        // Better a failure the queue can retry than a plausible-looking broken video.
        if total > 0, have < total {
            let detail = "\(name) truncated at \(have) of \(total) bytes"
            Log.transfer.error("\(detail, privacy: .public)")
            throw Failure.interrupted
        }

        return destination
    }

    /// One ranged request, using the machinery the whole file already had.
    private func fetchRange(
        _ url: URL,
        _ range: String,
        into name: String,
        reporting: @escaping @Sendable (Int64) -> Void
    ) async throws -> (URL, HTTPURLResponse?) {
        var request = URLRequest(url: url)
        // googlevideo refuses a request with no user agent, and hands back a 403 that
        // looks exactly like an expired signature.
        request.setValue(InnerTube.webClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(range, forHTTPHeaderField: "Range")

        let task = session.downloadTask(with: request)
        let destination = Paths.scratch.appendingPathComponent(name)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Registered before the task is resumed, not after: a cached or very
                // small response can complete before the next line runs, and a delegate
                // callback that finds no entry drops the download on the floor.
                delegate.register(
                    task: task, destination: destination,
                    progress: { written, _ in reporting(written) },
                    continuation: continuation
                )
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Pieces

    private static func sizeOnDisk(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    /// The total length of the resource, from `Content-Range: bytes 0-8388607/1234567890`.
    ///
    /// `expectedContentLength` is only the answer on a 200. On the 206 this code asks
    /// for, it is the length of *that range* — 8 MB — and taking it as the total means
    /// stopping after one chunk with a file that looks complete and is not.
    private static func totalLength(from response: HTTPURLResponse?) -> Int64? {
        guard let response else { return nil }
        if let header = response.value(forHTTPHeaderField: "Content-Range"),
           let slash = header.lastIndex(of: "/"),
           let total = Int64(header[header.index(after: slash)...]) {
            return total
        }
        // No Content-Range means the server ignored the request and sent the lot.
        return response.statusCode == 200 ? response.expectedContentLength : nil
    }

    /// Append one chunk to the file being assembled, then throw the chunk away.
    private static func append(_ chunk: URL, to destination: URL) throws {
        defer { try? FileManager.default.removeItem(at: chunk) }

        guard FileManager.default.fileExists(atPath: destination.path) else {
            try FileManager.default.moveItem(at: chunk, to: destination)
            return
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.seekToEnd()
        // Streamed in rather than read whole: a chunk is 8 MB and a phone under memory
        // pressure is exactly where this would be asked to fall over.
        let reader = try FileHandle(forReadingFrom: chunk)
        defer { try? reader.close() }
        while let block = try reader.read(upToCount: 1 << 20), !block.isEmpty {
            try handle.write(contentsOf: block)
        }
    }

    /// Re-adopt whatever the system was still doing while the app was away, so a task
    /// that finished during a relaunch is not left holding a temporary file forever.
    func discardOrphans() async {
        let tasks = await session.allTasks
        // `isUnclaimed` is a plain lock-guarded read, not an async call — an `await` in
        // the `where` clause would not compile.
        for task in tasks where delegate.isUnclaimed(task) {
            task.cancel()
        }
    }

    // MARK: - Delegate

    /// `URLSession` calls back on its own queue, so the bookkeeping lives in an actor
    /// and the delegate is the bridge into it.
    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private struct Pending {
            let destination: URL
            let progress: @Sendable (Int64, Int64) -> Void
            let continuation: CheckedContinuation<(URL, HTTPURLResponse?), Error>
        }

        private let lock = NSLock()
        private var pending: [Int: Pending] = [:]

        func register(
            task: URLSessionDownloadTask,
            destination: URL,
            progress: @escaping @Sendable (Int64, Int64) -> Void,
            continuation: CheckedContinuation<(URL, HTTPURLResponse?), Error>
        ) {
            lock.withLock {
                pending[task.taskIdentifier] = Pending(
                    destination: destination, progress: progress, continuation: continuation)
            }
        }

        func isUnclaimed(_ task: URLSessionTask) -> Bool {
            lock.withLock { pending[task.taskIdentifier] == nil }
        }

        private func take(_ identifier: Int) -> Pending? {
            lock.withLock { pending.removeValue(forKey: identifier) }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            let handler = lock.withLock { pending[downloadTask.taskIdentifier]?.progress }
            handler?(totalBytesWritten, totalBytesExpectedToWrite)
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            guard let job = take(downloadTask.taskIdentifier) else { return }

            // A 403 or 404 arrives here as a successfully downloaded *error page*, so
            // the status has to be checked or a few hundred bytes of HTML get muxed.
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                job.continuation.resume(throwing: Failure.http(response.statusCode))
                return
            }

            // The file at `location` is deleted the moment this method returns, so it
            // has to be moved now rather than in a Task.
            do {
                try? FileManager.default.removeItem(at: job.destination)
                try FileManager.default.moveItem(at: location, to: job.destination)
                job.continuation.resume(
                    returning: (job.destination, downloadTask.response as? HTTPURLResponse))
            } catch {
                job.continuation.resume(throwing: error)
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            // Success has already been resumed by didFinishDownloadingTo, which removes
            // the entry — so anything still here is a failure.
            guard let job = take(task.taskIdentifier) else { return }
            job.continuation.resume(throwing: error ?? Failure.interrupted)
        }
    }

    enum Failure: LocalizedError {
        case http(Int)
        case interrupted

        var errorDescription: String? {
            switch self {
            case .http(403):
                "YouTube rejected the download link (403). The link had probably expired "
                    + "— try again."
            case .http(let code):
                "The download failed with HTTP \(code)."
            case .interrupted:
                "The download was interrupted."
            }
        }
    }
}
