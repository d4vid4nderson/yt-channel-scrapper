import Foundation

/// Reads the saved channels ahead of time, so the first click on one is as instant as
/// the second.
///
/// `ListingCache` makes a channel quick to reopen, but a channel you have not opened since
/// launching the app — every one of them, the first time — still waited on a yt-dlp walk.
/// This walks them in the background instead: one at a time, first page only, at low
/// priority, most recently opened first, skipping any read in the last few hours. It
/// uses a `Scraper` of its own, so nothing on screen moves while it works.
@MainActor
final class ListingWarmer {
    private let scraper = Scraper()
    private var task: Task<Void, Never>?
    /// A channel read this recently is left alone.
    private let freshFor: TimeInterval = 6 * 3600

    var isWarming: Bool { task != nil }

    func warm(_ channels: [Channel], tab: ChannelTab) {
        guard task == nil else { return }
        let due = channels.filter {
            !ListingCache.shared.isFresh(ListingCache.key(url: $0.url, tab: tab), within: freshFor)
        }
        guard !due.isEmpty else { return }
        task = Task { [weak self] in
            for channel in due {
                guard let self, !Task.isCancelled else { break }
                self.scraper.start(rawURL: channel.url, tab: tab)
                while self.scraper.isBusy {
                    try? await Task.sleep(for: .milliseconds(400))
                    if Task.isCancelled { self.scraper.stop(); break }
                }
                // A breath between channels, so this never reads as a burst to YouTube.
                try? await Task.sleep(for: .seconds(1))
            }
            self?.scraper.reset()
            self?.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        scraper.stop()
    }
}
