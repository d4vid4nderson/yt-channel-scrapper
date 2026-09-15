import Foundation

/// Finding channels by name, so a channel you have not got a URL for is still reachable.
///
/// The Mac app streams these in as yt-dlp emits them. One InnerTube call returns all
/// twenty at once, so there is nothing to stream — the whole result arrives together.
@MainActor
@Observable
final class ChannelSearch {
    /// What a search is looking for. YouTube's own filter chips, and the only
    /// difference between the two calls is one `params` string.
    enum Scope: String, CaseIterable, Identifiable {
        case videos = "Videos"
        case channels = "Channels"
        var id: String { rawValue }
    }

    /// Changing this re-runs the current query rather than clearing it — switching the
    /// chip on YouTube does the same, and retyping would be a poor substitute.
    var scope: Scope = .videos {
        didSet { if scope != oldValue, !query.isEmpty { run(query) } }
    }

    private(set) var results: [Channel] = []
    private(set) var videos: [Video] = []
    private(set) var query = ""
    private(set) var isBusy = false
    private(set) var error: String?

    private var task: Task<Void, Never>?

    var hasResults: Bool {
        switch scope {
        case .channels: !results.isEmpty
        case .videos:   !videos.isEmpty
        }
    }

    func reset() {
        stop()
        results = []
        videos = []
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
        videos = []
        error = nil
        isBusy = true
        let scope = self.scope

        task = Task { [weak self] in
            guard let self else { return }
            do {
                switch scope {
                case .channels:
                    let found = try await YouTubeAPI.searchChannels(query: trimmed)
                    try Task.checkCancellation()
                    self.results = found
                    self.error = found.isEmpty
                        ? "No channels matched \"\(trimmed)\"." : nil
                case .videos:
                    let found = try await YouTubeAPI.searchVideos(query: trimmed)
                    try Task.checkCancellation()
                    self.videos = found
                    self.error = found.isEmpty
                        ? "No videos matched \"\(trimmed)\"." : nil
                }
                self.isBusy = false
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                self.isBusy = false
            }
        }
    }
}
