import SwiftUI

/// The downloads panel, as a tab.
///
/// On the Mac this hangs from the header as a drawer. A phone has no room for a drawer
/// and, more to the point, downloads are the thing you come back to check — so they get
/// a tab of their own with a badge on it.
struct DownloadsView: View {
    @Bindable var model: AppModel
    @State private var sharing: URL?

    var body: some View {
        NavigationStack {
            Group {
                if model.downloads.jobs.isEmpty {
                    Placeholder(
                        icon: "arrow.down.circle",
                        title: "Nothing downloading",
                        detail: "Swipe a video left, or select several and download them "
                            + "together. Finished files appear in Files under "
                            + "On My iPhone → YT Scraper."
                    )
                } else {
                    List {
                        ForEach(model.downloads.jobs) { job in
                            JobRow(job: job) { sharing = $0 }
                                .listRowBackground(Color.card)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        model.downloads.remove(job)
                                    } label: {
                                        Label(job.state.isFinished ? "Remove" : "Cancel",
                                              systemImage: job.state.isFinished ? "trash" : "xmark")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .ground()
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.downloads.hasFinished {
                    Button("Clear") { model.downloads.clearFinished() }
                }
            }
            .sheet(item: $sharing) { url in
                ShareSheet(items: [url])
            }
        }
    }
}

/// One job: what it is, how far along, and what it left on disk.
struct JobRow: View {
    let job: DownloadJob
    let onShare: (URL) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(video: job.video, width: 84, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(job.video.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(2)

                if job.state == .downloading || job.state == .processing {
                    ProgressView(value: job.state == .processing ? 1 : job.percent)
                        .tint(Palette.accent)
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                }

                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(job.state == .failed ? Palette.accent : Color.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // A finished file is only useful if you can get it somewhere. The share
            // sheet is how anything leaves an iOS app — a plain link would not work,
            // because the app cannot hand the system a file by pointing at it.
            if job.state == .done, let file = job.file {
                Button { onShare(file) } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.accent)
                        .tappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share \(job.video.title)")
            }
        }
        .padding(.vertical, 4)
    }

    private var status: String {
        // Every branch returns explicitly: Swift requires that once any one of them
        // does, and the `.done` case needs statements rather than an expression.
        switch job.state {
        case .downloading:
            let parts = [job.speedText, job.etaText].filter { !$0.isEmpty }
            return parts.isEmpty ? "Downloading…" : parts.joined(separator: "  ·  ")
        case .processing:
            return "Combining video and audio…"
        case .done:
            var parts = ["Saved"]
            if job.audioFile != nil { parts.append("with an m4a beside it") }
            if let audioError = job.audioError { parts.append("no m4a: \(audioError)") }
            return parts.joined(separator: "  ·  ")
        case .failed:
            return job.error ?? "Failed"
        default:
            return job.state.label
        }
    }
}

/// `UIActivityViewController`, which SwiftUI still has no native equivalent of for
/// sharing a file URL.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Lets a bare `URL` drive `.sheet(item:)`.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
