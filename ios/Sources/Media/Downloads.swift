import Foundation

/// The download queue: resolve, fetch, combine, save.
///
/// The iOS counterpart of the Mac app's `Core/Downloader.swift`. There the whole job is
/// one yt-dlp invocation whose stdout is parsed for progress; here each stage is
/// explicit, because there is no yt-dlp to delegate to:
///
///   1. `StreamResolver` picks the streams,
///   2. `Transfer` fetches each to the scratch directory,
///   3. `Muxer` writes one file into Documents,
///   4. the scratch copies are thrown away.
///
/// The `DownloadJob` model is shared with the Mac app unchanged, so the panel reads the
/// same way on both.
@MainActor
@Observable
final class Downloads {
    private(set) var jobs: [DownloadJob] = []

    /// Called after a job leaves a new file in Documents. `LocalFiles` reads the folder
    /// rather than keeping an index, so it has to be told when the folder changed.
    var didSave: (@MainActor () -> Void)?

    /// Two at a time. A phone on cellular gains nothing from more parallelism — the link
    /// is the limit, not the concurrency — and each running job holds a video and an
    /// audio file in the scratch directory before muxing.
    private static let concurrency = 2

    private var running: Set<UUID> = []
    /// One task per running job, kept so that cancelling a job can cancel the work
    /// rather than only marking it. `Transfer` cancels the underlying `URLSessionTask`
    /// from `withTaskCancellationHandler`, so this is what actually stops the bytes.
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Jobs whose half-written scratch files are worth continuing from. Only a pause
    /// puts a job in here. Everything else — a fresh start, a retry against another
    /// client — must not append to bytes that came from a different format, because the
    /// scratch name is per video and says nothing about which stream filled it.
    private var resumable: Set<UUID> = []
    /// Partial progress for paused jobs, keyed by job and stream. Held here rather than
    /// on `DownloadJob` because that model is shared with the Mac app, which has no
    /// concept of resuming — its downloads are one yt-dlp invocation.

    private static func key(_ job: DownloadJob, _ name: String) -> String {
        "\(job.id)-\(name)"
    }

    var active: Int { jobs.filter { !$0.state.isFinished }.count }
    var hasFinished: Bool { jobs.contains { $0.state.isFinished } }

    // MARK: - Queue

    func enqueue(_ videos: [Video], quality: Quality, alsoAudio: Bool) {
        for video in videos {
            // Re-asking for something already queued or running is a no-op rather than
            // a second copy on disk.
            guard !jobs.contains(where: { $0.video.id == video.id && !$0.state.isFinished })
            else { continue }
            jobs.append(DownloadJob(video: video, quality: quality, alsoAudio: alsoAudio))
        }
        start()
    }

    func cancel(_ job: DownloadJob) {
        job.state = .cancelled
        // Cancelling the task is the part that matters. Setting the state alone only
        // gets noticed at the next stage boundary, so a job cancelled two minutes into
        // a large file went on downloading the whole thing before it noticed.
        tasks[job.id]?.cancel()
        tasks[job.id] = nil
        running.remove(job.id)
        resumable.remove(job.id)
        forgetPartials(of: job)
        start()
    }

    /// Stop, but keep what has arrived so far.
    ///
    /// The state is set before the task is cancelled, because that is how `fetch` tells
    /// a pause from a cancel — both arrive as the same `Transfer.Failure.stopped`.
    func pause(_ job: DownloadJob) {
        guard job.state == .downloading || job.state == .queued else { return }
        job.state = .paused
        job.speed = nil
        job.eta = nil
        resumable.insert(job.id)
        tasks[job.id]?.cancel()
        tasks[job.id] = nil
        running.remove(job.id)
        start()
    }

    func resume(_ job: DownloadJob) {
        guard job.state == .paused else { return }
        job.state = .queued
        start()
    }

    func remove(_ job: DownloadJob) {
        if !job.state.isFinished { cancel(job) }
        forgetPartials(of: job)
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() {
        for job in jobs where job.state.isFinished { forgetPartials(of: job) }
        jobs.removeAll { $0.state.isFinished }
    }

    /// Where a job's two streams are written while being fetched.
    ///
    /// The extensions are not decoration. `AVURLAsset` decides what a file is from its
    /// path extension before reading a byte, so a perfectly good MP4 called
    /// `<id>.video` fails with AVFoundation -11828, "Cannot Open — this media format is
    /// not supported", while the identical bytes under `.mp4` open fine. The streams are
    /// always H.264 in MP4 and AAC in M4A, because `Stream.isMuxable` selects nothing
    /// else.
    private static func videoScratch(_ job: DownloadJob) -> String {
        "\(job.video.id).video.mp4"
    }

    private static func audioScratch(_ job: DownloadJob) -> String {
        "\(job.video.id).audio.m4a"
    }

    /// Throw away a job's half-downloaded bytes. Only for cancelling and failing —
    /// pausing keeps them, because they are what resuming continues from.
    ///
    /// The extensionless names are what earlier builds wrote, and the `.part` files are
    /// the in-flight chunk. All of them are listed so that a stale one cannot be
    /// resumed from: a partial as long as the resource makes the next range request
    /// start past the end, and googlevideo answers that with 416.
    private func forgetPartials(of job: DownloadJob) {
        let names = [Self.videoScratch(job), Self.audioScratch(job),
                     "\(job.video.id).video", "\(job.video.id).audio"]
        for name in names.flatMap({ [$0, "\($0).part"] }) {
            try? FileManager.default.removeItem(
                at: Paths.scratch.appendingPathComponent(name))
        }
    }

    /// Fill the free slots.
    ///
    /// One task per job rather than a single pump walking them in turn: a pump that
    /// `await`s each job runs exactly one at a time no matter what `concurrency` says,
    /// and gives cancellation nothing to aim at.
    private func start() {
        while let next = claimNext() {
            let job = next
            tasks[job.id] = Task { [weak self] in
                await self?.run(job)
                self?.finished(job)
            }
        }
    }

    /// A job has stopped, one way or another. Free its slot and pull in whatever is
    /// waiting behind it.
    private func finished(_ job: DownloadJob) {
        tasks[job.id] = nil
        running.remove(job.id)
        start()
    }

    private func claimNext() -> DownloadJob? {
        // `!running.contains` is load-bearing, not belt and braces. A claimed job keeps
        // `.queued` until its task actually starts, which is some time after this
        // returns — so matching on state alone hands the same job back on the next turn
        // of the loop, forever. The old single pump hid this by awaiting each job.
        guard running.count < Self.concurrency,
              let next = jobs.first(where: { $0.state == .queued && !running.contains($0.id) })
        else { return nil }
        running.insert(next.id)
        return next
    }

    // MARK: - One job

    /// A fetch YouTube refused, carrying the client whose URL it refused so the next
    /// attempt can ask a different one.
    private struct Refused: Error { let client: String }

    private func run(_ job: DownloadJob) async {
        guard job.state == .queued else { return }

        // Clients whose URLs have already come back 403. `StreamResolver` cannot learn
        // this for itself: it returns the first rung that yields streams, and the
        // refusal happens later, while fetching. Feeding them back is what lets the
        // ladder keep walking instead of choosing the same dead rung every time.
        var refused: Set<String> = []

        do {
            while true {
                do {
                    try await attempt(job, refused: refused)
                    break
                } catch let stop as Refused {
                    refused.insert(stop.client)
                    let detail = "\(stop.client) refused \(job.video.id), trying the next client"
                    Log.transfer.info("\(detail, privacy: .public)")
                    // The bar restarts with the new source rather than carrying a
                    // percentage that belonged to a download now abandoned.
                    job.percent = 0
                    job.speed = nil
                    job.eta = nil
                }
            }

            job.percent = 1
            job.speed = nil
            job.eta = nil
            job.state = .done
            Log.transfer.info("saved \(job.video.id, privacy: .public)")
            didSave?()

        } catch is CancellationError {
            if job.state != .paused { resumable.remove(job.id) }
            // Pausing and cancelling both cancel the task, so they arrive identically.
            // The state separates them: `pause` sets it before cancelling, and leaves
            // the half-written scratch file for the next attempt to continue from.
            if job.state == .paused {
                Log.transfer.info("paused \(job.video.id, privacy: .public)")
            } else {
                job.state = .cancelled
                Log.transfer.info("cancelled \(job.video.id, privacy: .public)")
            }
        } catch {
            // A failed job's partial bytes are not worth continuing from: the retry
            // re-resolves and may well be handed a different format.
            resumable.remove(job.id)
            forgetPartials(of: job)
            job.error = Self.describe(error)
            job.state = .failed
            let detail = "failed \(job.video.id): \(error.localizedDescription)"
            Log.transfer.error("\(detail, privacy: .public)")
        }
    }

    /// One pass at a job: resolve, fetch, mux.
    ///
    /// A 403 anywhere in the fetch becomes `Refused` so the caller can retry against a
    /// different client. Everything else propagates and fails the job, because a codec
    /// the muxer cannot write will not write any better from another rung.
    private func attempt(_ job: DownloadJob, refused: Set<String>) async throws {
        // Continue only what a pause left behind. Anything else starts clean: appending
        // 1080p bytes onto a 720p partial would produce a file that is neither.
        if resumable.remove(job.id) == nil { forgetPartials(of: job) }
        job.state = .downloading
        let resolved = try await StreamResolver.resolve(
            videoID: job.video.id, for: .download(job.quality), refused: refused)
        job.totalBytes = resolved.expectedBytes
        try checkCancelled(job)

        do {

            switch resolved.source {
            case .hls:
                // Playback's shape, never a download's — `StreamResolver` does not
                // return it for `.download`, and muxing an HLS master is not a thing.
                throw Muxer.Failure.unsupportedCodec

            case .audioOnly(let audio):
                let name = Paths.filename(title: job.video.title, id: job.video.id,
                                          extension: "m4a")
                let scratch = try await fetch(audio.url, as: Self.audioScratch(job),
                                              expecting: resolved.expectedBytes, job: job)
                try checkCancelled(job)
                job.state = .processing
                let destination = Paths.available(Paths.downloads.appendingPathComponent(name))
                try await Muxer.extractAudio(from: scratch, into: destination)
                try? FileManager.default.removeItem(at: scratch)
                job.file = destination

            case .pair(let video, let audio):
                let total = resolved.expectedBytes
                let videoFile = try await fetch(video.url, as: Self.videoScratch(job),
                                                expecting: total, job: job)
                try checkCancelled(job)

                var audioFile: URL?
                if let audio {
                    audioFile = try await fetch(
                        audio.url, as: Self.audioScratch(job), expecting: total, job: job,
                        alreadyDone: video.contentLength ?? 0)
                }
                try checkCancelled(job)

                job.state = .processing
                let name = Paths.filename(title: job.video.title, id: job.video.id,
                                          extension: "mp4")
                let destination = Paths.available(Paths.downloads.appendingPathComponent(name))
                try await Muxer.combine(video: videoFile, audio: audioFile, into: destination)
                job.file = destination

                // The mp3 sidecar the Mac writes, as an m4a — see `Muxer.extractAudio`.
                // A failure here is recorded separately: the video arrived, and a
                // missing sidecar must not read as a failed download.
                if job.wantsSidecarAudio, let audioFile {
                    do {
                        let sidecar = Paths.available(destination
                            .deletingPathExtension().appendingPathExtension("m4a"))
                        try await Muxer.extractAudio(from: audioFile, into: sidecar)
                        job.audioFile = sidecar
                    } catch {
                        job.audioError = error.localizedDescription
                    }
                }

                try? FileManager.default.removeItem(at: videoFile)
                if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
            }

        } catch Transfer.Failure.http(403) {
            throw Refused(client: resolved.client)
        }
    }

    private func checkCancelled(_ job: DownloadJob) throws {
        if job.state == .cancelled { throw CancellationError() }
    }

    /// One stream, reporting progress into the job.
    ///
    /// `expecting` is the combined size of both streams, and `alreadyDone` the bytes the
    /// earlier stream contributed — without them the audio pass would restart the bar at
    /// zero, which is the same reason the Mac app probes for a combined total.
    private func fetch(
        _ url: URL,
        as name: String,
        expecting total: Int64?,
        job: DownloadJob,
        alreadyDone: Int64 = 0
    ) async throws -> URL {
        let started = Date()
        let meter = Meter()

        return try await Transfer.shared.download(url, named: name) { written, expected in
            let done = alreadyDone + written
            let overall = total ?? (expected > 0 ? alreadyDone + expected : 0)
            let elapsed = Date().timeIntervalSince(started)
            let rate = elapsed > 0.5 ? Double(written) / elapsed : nil
            let snapshot = Meter.Reading(
                percent: overall > 0 ? min(Double(done) / Double(overall), 1) : 0,
                speed: rate,
                eta: rate.flatMap { rate -> Int? in
                    guard rate > 0, overall > done else { return nil }
                    return Int(Double(overall - done) / rate)
                }
            )
            meter.publish(snapshot, to: job)
        }
    }

    /// Progress callbacks arrive on the session's queue several times a second; this
    /// hops them to the main actor and drops the ones the UI would not have shown
    /// anyway, so a download does not spend its time re-laying-out a progress bar.
    private final class Meter: @unchecked Sendable {
        struct Reading: Sendable {
            let percent: Double
            let speed: Double?
            let eta: Int?
        }

        private let lock = NSLock()
        private var lastPublished = Date.distantPast

        func publish(_ reading: Reading, to job: DownloadJob) {
            let due = lock.withLock { () -> Bool in
                guard Date().timeIntervalSince(lastPublished) > 0.2 else { return false }
                lastPublished = Date()
                return true
            }
            guard due else { return }
            Task { @MainActor in
                // Only a job that is still running may be told it is downloading.
                // These readings are already in flight when the user pauses, and one
                // landing afterwards used to flip `.paused` back to `.downloading` —
                // which made the pause look like it failed, made `run` record a cancel
                // instead of a pause, and left the half-written file to be appended to
                // by the next attempt.
                guard job.state == .downloading || job.state == .queued else { return }
                job.state = .downloading
                job.percent = reading.percent
                job.speed = reading.speed
                job.eta = reading.eta
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let known = error as? LocalizedError, let text = known.errorDescription {
            return text
        }
        return error.localizedDescription
    }
}
