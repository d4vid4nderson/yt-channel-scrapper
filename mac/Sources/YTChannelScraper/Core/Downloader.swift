import Foundation

/// The download queue: three at a time, each stepping down the fallback ladder.
@MainActor
@Observable
final class Downloader {
    static let maxConcurrent = 3

    private(set) var jobs: [DownloadJob] = []

    private var waiting: [DownloadJob] = []
    private var running: Set<UUID> = []
    private var streams: [UUID: ProcessStream] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Jobs the user removed mid-flight; the runner checks this before reporting failure
    /// so a deliberate kill is not shown as an error.
    private var cancelled: Set<UUID> = []

    var activeCount: Int { jobs.filter { !$0.state.isFinished }.count }
    var hasFinished: Bool { jobs.contains { $0.state.isFinished } }

    func enqueue(_ videos: [Video], quality: Quality) {
        for video in videos {
            let job = DownloadJob(video: video, quality: quality)
            jobs.append(job)
            waiting.append(job)
        }
        pump()
    }

    func remove(_ job: DownloadJob) {
        cancelled.insert(job.id)
        streams[job.id]?.terminate()
        tasks[job.id]?.cancel()
        streams[job.id] = nil
        tasks[job.id] = nil
        running.remove(job.id)
        waiting.removeAll { $0.id == job.id }
        jobs.removeAll { $0.id == job.id }
        pump()
    }

    func clearFinished() {
        jobs.removeAll { $0.state.isFinished }
    }

    func cancelAll() {
        for job in jobs where !job.state.isFinished { remove(job) }
    }

    private func pump() {
        while running.count < Self.maxConcurrent, !waiting.isEmpty {
            let job = waiting.removeFirst()
            running.insert(job.id)
            tasks[job.id] = Task { [weak self] in
                await self?.run(job)
                self?.finish(job)
            }
        }
    }

    private func finish(_ job: DownloadJob) {
        running.remove(job.id)
        streams[job.id] = nil
        tasks[job.id] = nil
        pump()
    }

    // MARK: - One job

    private func run(_ job: DownloadJob) async {
        let ladder = YtDlp.ladder
        var lastError: String?

        for (index, rung) in ladder.enumerated() {
            if cancelled.contains(job.id) { return }

            job.state = .downloading
            job.error = nil
            // Probe first purely to learn the combined size of the streams that will be
            // fetched; without it the first of two merged streams reads as 100%.
            let expected = await probe(job, rung: rung)

            do {
                try await download(job, rung: rung, expected: expected)
                job.state = .done
                job.percent = 100
                job.error = nil
                return
            } catch {
                if cancelled.contains(job.id) { return }
                lastError = Self.tidy(error)
                if index < ladder.count - 1 {
                    job.state = .retrying
                    job.percent = 0
                    job.error = lastError
                    // A browser holding no YouTube cookies fails instantly and costs
                    // nothing; only back off once a rung has actually talked to YouTube.
                    if rung.backsOff {
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
            }
        }

        if cancelled.contains(job.id) { return }
        job.state = .failed
        job.error = lastError ?? "Download failed"
    }

    /// Best-effort combined size of the streams about to be fetched. Zero means
    /// "unknown", and progress falls back to whatever each stream reports.
    private func probe(_ job: DownloadJob, rung: YtDlp.Rung) async -> Int64 {
        let stream = ProcessStream(
            executable: Paths.ytdlp,
            arguments: YtDlp.probeArguments(video: job.video, quality: job.quality, rung: rung),
            environment: YtDlp.environment
        )
        streams[job.id] = stream
        defer { streams[job.id] = nil }

        var total: Int64 = 0
        do {
            for try await line in stream.lines() {
                guard line.hasPrefix("{"), let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                let formats = (json["requested_formats"] as? [[String: Any]]) ?? [json]
                total = formats.reduce(into: Int64(0)) { sum, format in
                    let size = (format["filesize"] as? NSNumber)?.int64Value
                        ?? (format["filesize_approx"] as? NSNumber)?.int64Value ?? 0
                    sum += size
                }
            }
        } catch {
            return 0
        }
        return total
    }

    private func download(_ job: DownloadJob, rung: YtDlp.Rung, expected: Int64) async throws {
        let stream = ProcessStream(
            executable: Paths.ytdlp,
            arguments: YtDlp.downloadArguments(video: job.video, quality: job.quality, rung: rung),
            environment: YtDlp.environment
        )
        streams[job.id] = stream
        defer { streams[job.id] = nil }

        // A merged download runs two passes, each reporting 0-100% of its own file, so
        // bytes are summed per stream against the combined expected size instead.
        var got: [String: Int64] = [:]

        for try await line in stream.lines() {
            if cancelled.contains(job.id) {
                stream.terminate()
                throw CancellationError()
            }
            if line.hasPrefix(YtDlp.finalPrefix) {
                let path = String(line.dropFirst(YtDlp.finalPrefix.count))
                if !path.isEmpty { job.file = URL(fileURLWithPath: path) }
                continue
            }
            guard line.hasPrefix(YtDlp.progressPrefix),
                  let progress = Progress(line: line) else { continue }

            switch progress.status {
            case "downloading":
                got[progress.filename] = progress.downloaded
                let total = expected > 0 ? expected : progress.total
                let sum = got.values.reduce(0, +)
                job.state = .downloading
                job.percent = total > 0 ? min(Double(sum) / Double(total) * 100, 100) : 0
                job.speed = progress.speed
                job.eta = progress.eta
            case "finished":
                got[progress.filename] = progress.total > 0 ? progress.total : (got[progress.filename] ?? 0)
                let sum = got.values.reduce(0, +)
                // Only the last stream landing means the file is really done; earlier
                // ones just hand over to the next pass.
                if expected <= 0 || Double(sum) >= Double(expected) * 0.995 {
                    job.state = .processing
                    job.percent = 100
                    job.speed = nil
                    job.eta = nil
                }
            default:
                break
            }
        }
    }

    /// One parsed `--progress-template` line.
    private struct Progress {
        let status: String
        let downloaded: Int64
        let total: Int64
        let speed: Double?
        let eta: Int?
        let filename: String

        init?(line: String) {
            let body = line.dropFirst(YtDlp.progressPrefix.count)
            // filename is last so that a separator inside a path cannot shift the fields
            let parts = body.split(separator: "\u{1F}", maxSplits: 6, omittingEmptySubsequences: false)
            guard parts.count == 7 else { return nil }
            func number(_ raw: Substring) -> Double? {
                raw == "NA" || raw.isEmpty ? nil : Double(raw)
            }
            status = String(parts[0])
            downloaded = Int64(number(parts[1]) ?? 0)
            // total_bytes is NA for a stream whose size is only estimated
            total = Int64(number(parts[2]) ?? number(parts[3]) ?? 0)
            speed = number(parts[4])
            eta = number(parts[5]).map(Int.init)
            filename = String(parts[6])
        }
    }

    private static func tidy(_ error: Error) -> String {
        guard let failure = error as? ProcessStream.Failure else {
            return error.localizedDescription
        }
        let lines = failure.message.split(separator: "\n")
        let line = lines.last(where: { $0.contains("ERROR") }) ?? lines.last ?? ""
        var text = line.replacingOccurrences(of: "ERROR: ", with: "")
        // yt-dlp prefixes its messages with the extractor that raised them, e.g.
        // "[youtube:tab] ..." — noise to anyone who is not debugging yt-dlp.
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = String(text[text.index(after: close)...])
        }
        return String(text.trimmingCharacters(in: .whitespaces).prefix(300))
    }
}
