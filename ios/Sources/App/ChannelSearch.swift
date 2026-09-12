import Foundation

/// Finding channels by name, so a channel you have not got a URL for is still reachable.
///
/// The Mac app streams these in as yt-dlp emits them. One InnerTube call returns all
/// twenty at once, so there is nothing to stream — the whole result arrives together.
@MainActor
@Observable
final class ChannelSearch {
    private(set) var results: [Channel] = []
    private(set) var query = ""
    private(set) var isBusy = false
    private(set) var error: String?

    private var task: Task<Void, Never>?

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
        isBusy = false
    }

    func run(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        query = trimmed
        results = []
        error = nil
        isBusy = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let found = try await YouTubeAPI.searchChannels(query: trimmed)
                try Task.checkCancellation()
                self.results = found
                self.error = found.isEmpty ? "No channels matched \"\(trimmed)\"." : nil
                self.isBusy = false
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                self.isBusy = false
            }
        }
    }
}
