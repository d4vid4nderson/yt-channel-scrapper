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
    private var pump: Task<Void, Never>?

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
        running.remove(job.id)
        start()
    }

    func remove(_ job: DownloadJob) {
        if !job.state.isFinished { cancel(job) }
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() {
        jobs.removeAll { $0.state.isFinished }
    }

    private func start() {
        guard pump == nil else { return }
        pump = Task { [weak self] in
            while let next = self?.claimNext() {
                await self?.run(next)
            }
            self?.pump = nil
        }
    }

    private func claimNext() -> DownloadJob? {
        guard running.count < Self.concurrency,
              let next = jobs.first(where: { $0.state == .queued })
        else { return nil }
        running.insert(next.id)
        return next
    }

    // MARK: - One job

    /// A fetch YouTube refused, carrying the client whose URL it refused so the next
    /// attempt can ask a different one.
    private struct Refused: Error { let client: String }

    private func run(_ job: DownloadJob) async {
        defer { running.remove(job.id) }
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
            job.state = .cancelled
        } catch {
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
        job.state = .downloading
        let resolved = try await StreamResolver.resolve(
            videoID: job.video.id, for: .download(job.quality), refused: refused)
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
                let scratch = try await fetch(audio.url, as: "\(job.video.id).audio",
                                              expecting: resolved.expectedBytes, job: job)
                try checkCancelled(job)
                job.state = .processing
                let destination = Paths.available(Paths.downloads.appendingPathComponent(name))
                try await Muxer.extractAudio(from: scratch, into: destination)
                try? FileManager.default.removeItem(at: scratch)
                job.file = destination

            case .pair(let video, let audio):
                let total = resolved.expectedBytes
                let videoFile = try await fetch(video.url, as: "\(job.video.id).video",
                                                expecting: total, job: job)
                try checkCancelled(job)

                var audioFile: URL?
                if let audio {
                    audioFile = try await fetch(
                        audio.url, as: "\(job.video.id).audio", expecting: total, job: job,
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
                guard !job.state.isFinished else { return }
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
