import Foundation

/// The loudness of what is playing, over its whole length, and its tempo.
///
/// The player cannot be asked: previews play as HLS, and AVFoundation will not tap the
/// audio of an HLS stream. So the audio stream is fetched a second time and decoded on
/// the side — ffmpeg, which the app already ships, reading it straight from YouTube and
/// writing raw samples as they arrive — and the waveform fills in from the start while
/// the track plays. Nothing is saved; it is a picture of the sound, rebuilt per track.
///
/// Costs a second download of the audio (about 1 MB a minute), and only runs for what
/// is in the Now Playing module.
@MainActor
@Observable
final class TrackAnalysis {
    /// Envelope values per second of audio.
    nonisolated static let rate: Double = 100

    private(set) var videoID: String?
    /// RMS loudness, one value per 1/`rate` s.
    private(set) var envelope: [Float] = []
    /// What full height means: the loudest quarter-second so far.
    private(set) var peak: Float = 0
    /// Only when the beat is clear enough to name — speech has no tempo worth showing.
    private(set) var bpm: Double?
    /// When the first beat falls, in seconds, so the beat light can land on the beat.
    private(set) var beatPhase: Double = 0

    private var task: Task<Void, Never>?
    private let decoder = DecoderBox()
    private var lastTempoAt = 0

    func analyse(_ video: Video) {
        guard video.id != videoID else { return }
        cancel()
        videoID = video.id
        guard Paths.hasFFmpeg else { return }
        let decoder = self.decoder
        let id = video.id
        task = Task { [weak self] in
            guard let url = await Self.audioURL(for: video), !Task.isCancelled else { return }
            weak let owner = self
            await Task.detached(priority: .utility) {
                decoder.run(url) { chunk in
                    await owner?.absorb(chunk, for: id)
                }
            }.value
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        decoder.stop()
        videoID = nil
        envelope = []
        peak = 0
        bpm = nil
        beatPhase = 0
        lastTempoAt = 0
    }

    /// Loudness at `seconds`, 0…1, or nil where the analysis has not reached yet.
    func level(at seconds: Double) -> Float? {
        let i = Int(seconds * Self.rate)
        guard i >= 0, i < envelope.count, peak > 0 else { return nil }
        return min(1, envelope[i] / peak)
    }

    private func absorb(_ chunk: [Float], for id: String) {
        // A decoder still draining after the track changed is not this track's sound.
        guard id == videoID else { return }
        envelope.append(contentsOf: chunk)
        // Quarter-second means, so one click does not set the scale for the whole track.
        stride(from: 0, to: chunk.count - 24, by: 25).forEach { start in
            let mean = chunk[start..<start + 25].reduce(0, +) / 25
            peak = max(peak, mean * 1.15)
        }
        // A tempo from the first 30 s, refined at 90 s and 180 s.
        let seconds = envelope.count / Int(Self.rate)
        for mark in [30, 90, 180] where seconds >= mark && lastTempoAt < mark {
            lastTempoAt = mark
            let sample = envelope
            Task.detached(priority: .utility) { [weak self] in
                let found = Self.tempo(sample)
                await MainActor.run {
                    guard let self, self.envelope.count >= sample.count else { return }
                    self.bpm = found?.bpm
                    self.beatPhase = found?.phase ?? 0
                }
            }
        }
    }

    // MARK: - Finding the audio

    private static func audioURL(for video: Video) async -> URL? {
        for rung in YtDlp.previewLadder {
            let stream = ProcessStream(
                executable: Paths.ytdlp,
                arguments: ["--ignore-config", "--no-warnings", "--no-playlist", "-g",
                            "-f", "ba[ext=m4a]/ba"] + rung.arguments + [video.url.absoluteString],
                environment: YtDlp.environment
            )
            do {
                for try await line in stream.lines() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("http"), let url = URL(string: trimmed) { return url }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Tempo

    /// Beats per minute and the first beat's time, from the envelope's onsets: the rises
    /// in loudness, autocorrelated across the lags that 60–180 BPM would put between
    /// them. Folded into 80–160, where a listener would count it. Nil when no lag stands
    /// out from the rest — the track has no steady beat.
    nonisolated static func tempo(_ envelope: [Float]) -> (bpm: Double, phase: Double)? {
        let rate = Self.rate
        // Skip an intro where there is one, and look at no more than a minute.
        let start = envelope.count > Int(rate * 50) ? Int(rate * 10) : 0
        let end = min(envelope.count, start + Int(rate * 60))
        guard end - start > Int(rate * 15) else { return nil }
        var onset = [Double](repeating: 0, count: end - start)
        for i in (start + 1)..<end {
            let rise = log(Double(envelope[i]) + 1e-4) - log(Double(envelope[i - 1]) + 1e-4)
            onset[i - start] = max(0, rise)
        }
        let mean = onset.reduce(0, +) / Double(onset.count)
        onset = onset.map { $0 - mean }

        func correlation(_ lag: Int) -> Double {
            var sum = 0.0
            for i in 0..<(onset.count - lag) { sum += onset[i] * onset[i + lag] }
            return sum
        }
        let zero = correlation(0)
        guard zero > 0 else { return nil }
        let lags = Int(rate * 60 / 180)...Int(rate * 60 / 60)
        let scores = lags.map { ($0, correlation($0)) }
        guard let best = scores.max(by: { $0.1 < $1.1 }), best.1 / zero > 0.08 else { return nil }

        // Between samples: a parabola through the peak and its neighbours.
        var lag = Double(best.0)
        if best.0 > lags.lowerBound, best.0 < lags.upperBound {
            let a = correlation(best.0 - 1), b = best.1, c = correlation(best.0 + 1)
            let denominator = a - 2 * b + c
            if denominator != 0 { lag += 0.5 * (a - c) / denominator }
        }
        var bpm = rate * 60 / lag
        while bpm < 80 { bpm *= 2 }
        while bpm > 160 { bpm /= 2 }

        // Where along one period the onsets pile up is where the beat falls.
        let period = rate * 60 / bpm
        var bestPhase = 0, bestSum = -Double.infinity
        for p in 0..<max(1, Int(period)) {
            var sum = 0.0
            var i = Double(p)
            while Int(i) < onset.count { sum += onset[Int(i)]; i += period }
            if sum > bestSum { bestSum = sum; bestPhase = p }
        }
        return (bpm, (Double(start) + Double(bestPhase)) / rate)
    }
}

/// ffmpeg, decoding to mono 8 kHz floats on stdout, turned into the envelope a chunk at a
/// time. Lives off the main actor: it blocks on the pipe for as long as the track is.
private final class DecoderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func stop() {
        lock.lock()
        process?.terminate()
        process = nil
        lock.unlock()
    }

    func run(_ url: URL, deliver: @escaping @Sendable ([Float]) async -> Void) {
        let process = Process()
        process.executableURL = FFmpeg.executable
        process.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error",
                             "-i", url.absoluteString, "-vn", "-ac", "1", "-ar", "8000",
                             "-f", "f32le", "pipe:1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        lock.lock()
        self.process?.terminate()
        self.process = process
        lock.unlock()
        do { try process.run() } catch { return }

        let hop = 80                          // 10 ms at 8 kHz
        var carry = Data()
        var window: [Float] = []
        var sumSquares: Float = 0
        var pending: [Float] = []
        let reader = pipe.fileHandleForReading
        while true {
            let data = reader.availableData
            if data.isEmpty { break }
            carry.append(data)
            let whole = carry.count / 4 * 4
            carry.withUnsafeBytes { raw in
                let floats = raw.bindMemory(to: Float.self)
                for i in 0..<(whole / 4) {
                    let v = floats[i]
                    sumSquares += v * v
                    window.append(v)
                    if window.count == hop {
                        pending.append((sumSquares / Float(hop)).squareRoot())
                        window.removeAll(keepingCapacity: true)
                        sumSquares = 0
                    }
                }
            }
            carry.removeFirst(whole)
            // Half a second of envelope at a time is plenty for a picture to grow by.
            if pending.count >= 50 {
                let chunk = pending
                pending = []
                let done = DispatchSemaphore(value: 0)
                Task { await deliver(chunk); done.signal() }
                done.wait()
            }
        }
        if !pending.isEmpty {
            let chunk = pending
            let done = DispatchSemaphore(value: 0)
            Task { await deliver(chunk); done.signal() }
            done.wait()
        }
    }
}
