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
    static let sessionIdentifier = "com.moregroup.ytchannelscraper.transfer"

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
    func download(
        _ url: URL,
        named name: String,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url)
        // googlevideo refuses a request with no user agent, and hands back a 403 that
        // looks exactly like an expired signature.
        request.setValue(InnerTube.webClient.userAgent, forHTTPHeaderField: "User-Agent")
        // Ask for the whole thing explicitly. Without a Range header googlevideo
        // throttles hard after the first few megabytes.
        request.setValue("bytes=0-", forHTTPHeaderField: "Range")

        let task = session.downloadTask(with: request)
        let destination = Paths.scratch.appendingPathComponent(name)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Registered before the task is resumed, not after: a cached or very
                // small response can complete before the next line runs, and a delegate
                // callback that finds no entry drops the download on the floor.
                delegate.register(
                    task: task, destination: destination,
                    progress: onProgress, continuation: continuation
                )
                task.resume()
            }
        } onCancel: {
            task.cancel()
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
            let continuation: CheckedContinuation<URL, Error>
        }

        private let lock = NSLock()
        private var pending: [Int: Pending] = [:]

        func register(
            task: URLSessionDownloadTask,
            destination: URL,
            progress: @escaping @Sendable (Int64, Int64) -> Void,
            continuation: CheckedContinuation<URL, Error>
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
                job.continuation.resume(returning: job.destination)
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
