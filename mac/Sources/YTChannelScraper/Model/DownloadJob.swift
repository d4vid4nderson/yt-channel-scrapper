import Foundation

/// A single queued/running/finished download. The UI reads these; `Downloader` writes them.
@MainActor
@Observable
final class DownloadJob: Identifiable {
    enum State: Equatable, Sendable {
        case queued, downloading, retrying, processing, done, failed, cancelled

        var isFinished: Bool { self == .done || self == .failed || self == .cancelled }

        var label: String {
            switch self {
            case .queued:      "Queued"
            case .downloading: "Downloading"
            case .retrying:    "Retrying"
            case .processing:  "Processing"
            case .done:        "Done"
            case .failed:      "Failed"
            case .cancelled:   "Cancelled"
            }
        }
    }

    let id = UUID()
    let video: Video
    let quality: Quality

    var state: State = .queued
    var percent: Double = 0
    var speed: Double?          // bytes/sec
    var eta: Int?               // seconds
    var file: URL?
    var error: String?

    init(video: Video, quality: Quality) {
        self.video = video
        self.quality = quality
    }

    var speedText: String {
        guard let speed, speed > 0, state == .downloading else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
    }

    var etaText: String {
        guard let eta, eta > 0, state == .downloading else { return "" }
        return eta >= 60 ? "\(eta / 60)m \(eta % 60)s left" : "\(eta)s left"
    }
}
