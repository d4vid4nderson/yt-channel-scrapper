import Foundation

/// Runs a child process and hands back its stdout as an async sequence of lines.
///
/// Both callers need to stop a run early — the scraper when a page fills, the downloader
/// when the user removes a job — so cancelling the stream has to kill the process. That
/// is wired through `onTermination`: breaking out of the `for await` loop is enough.
final class ProcessStream: @unchecked Sendable {
    struct Failure: Error {
        let code: Int32
        let message: String
    }

    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private let lock = NSLock()
    private var outBuffer = Data()
    private var errBuffer = Data()

    init(executable: URL, arguments: [String], environment: [String: String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outPipe
        process.standardError = errPipe
    }

    /// yt-dlp writes the useful diagnostics here; kept for the error message on failure.
    var errorText: String {
        lock.withLock { String(decoding: errBuffer, as: UTF8.self) }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func lines() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                for line in self.take(chunk, into: \.outBuffer) { continuation.yield(line) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                self.lock.withLock { self.errBuffer.append(chunk) }
            }

            process.terminationHandler = { [weak self] proc in
                guard let self else { return }
                self.outPipe.fileHandleForReading.readabilityHandler = nil
                self.errPipe.fileHandleForReading.readabilityHandler = nil
                // Whatever is left in the pipes after the process exits never triggers a
                // readability callback, so it has to be drained by hand or the last line
                // of output — often the one carrying the final filepath — is lost.
                let restOut = self.outPipe.fileHandleForReading.availableData
                let restErr = self.errPipe.fileHandleForReading.availableData
                if !restOut.isEmpty {
                    for line in self.take(restOut, into: \.outBuffer) { continuation.yield(line) }
                }
                if !restErr.isEmpty { self.lock.withLock { self.errBuffer.append(restErr) } }
                let trailing = self.lock.withLock { () -> String? in
                    defer { self.outBuffer.removeAll() }
                    return self.outBuffer.isEmpty
                        ? nil : String(decoding: self.outBuffer, as: UTF8.self)
                }
                if let trailing, !trailing.isEmpty { continuation.yield(trailing) }

                if proc.terminationReason == .uncaughtSignal || proc.terminationStatus == 0 {
                    continuation.finish()   // a signal means we killed it deliberately
                } else {
                    continuation.finish(
                        throwing: Failure(code: proc.terminationStatus, message: self.errorText)
                    )
                }
            }

            continuation.onTermination = { [weak self] _ in
                self?.terminate()
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Append a chunk to one of the buffers and pop off whatever complete lines it made.
    private func take(_ chunk: Data, into keyPath: ReferenceWritableKeyPath<ProcessStream, Data>) -> [String] {
        lock.withLock {
            self[keyPath: keyPath].append(chunk)
            var lines: [String] = []
            while let newline = self[keyPath: keyPath].firstIndex(of: 0x0A) {
                let slice = self[keyPath: keyPath][self[keyPath: keyPath].startIndex..<newline]
                self[keyPath: keyPath].removeSubrange(self[keyPath: keyPath].startIndex...newline)
                var line = String(decoding: slice, as: UTF8.self)
                if line.hasSuffix("\r") { line.removeLast() }
                lines.append(line)
            }
            return lines
        }
    }
}
