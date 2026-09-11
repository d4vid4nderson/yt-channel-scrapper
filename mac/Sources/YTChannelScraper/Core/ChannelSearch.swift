import Foundation

/// Finds channels by name, so a channel you have not got a URL for is still reachable.
///
/// Results stream in the way a scrape's do — the first hit is usually the one you meant,
/// and it should not have to wait for the tenth.
@MainActor
@Observable
final class ChannelSearch {
    static let resultCount = 20

    private(set) var results: [Channel] = []
    private(set) var query = ""
    private(set) var isBusy = false
    private(set) var error: String?

    private var task: Task<Void, Never>?
    private var stream: ProcessStream?

    var hasResults: Bool { !results.isEmpty }

    func reset() {
        stop()
        results = []
        query = ""
        error = nil
    }

    func stop() {
        task?.cancel()
        task = nil
        stream?.terminate()
        stream = nil
        isBusy = false
    }

    func run(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        results = []
        error = nil
        query = trimmed
        isBusy = true

        task = Task { [weak self] in
            guard let self else { return }
            var seen: Set<String> = []
            let stream = ProcessStream(
                executable: Paths.ytdlp,
                arguments: YtDlp.channelSearchArguments(query: trimmed, count: Self.resultCount),
                environment: YtDlp.environment
            )
            self.stream = stream
            do {
                for try await line in stream.lines() {
                    try Task.checkCancellation()
                    guard line.hasPrefix("{"),
                          let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let channel = Channel(searchJSON: json),
                          seen.insert(channel.id).inserted
                    else { continue }
                    self.results.append(channel)
                }
                if self.results.isEmpty {
                    self.error = "No channels found for “\(trimmed)”."
                }
            } catch is CancellationError {
                return      // stop() already cleared the state
            } catch {
                // A search that returned nothing exits non-zero; with hits in hand that
                // is just the end of the listing, not a failure.
                if self.results.isEmpty {
                    self.error = "Could not search YouTube. Check your connection and try again."
                }
            }
            self.stream = nil
            self.isBusy = false
        }
    }
}
