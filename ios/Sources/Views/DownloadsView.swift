import SwiftUI
import UIKit

/// The downloads panel, as a tab.
///
/// On the Mac this hangs from the header as a drawer. A phone has no room for a drawer
/// and, more to the point, downloads are the thing you come back to check — so they get
/// a tab of their own with a badge on it.
///
/// Two lists, not one. Transfers are this run's jobs and they disappear with the process;
/// "On this phone" is the folder itself, which is what is still there tomorrow. Before
/// the second section a finished download became unreachable the moment the app was
/// killed — the file was in Files.app, and nowhere in the app that made it.
struct DownloadsView: View {
    @Bindable var model: AppModel
    @State private var sharing: URL?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            Group {
                if model.downloads.jobs.isEmpty && model.localFiles.isEmpty {
                    Placeholder(
                        icon: "arrow.down.circle",
                        title: "Nothing downloaded yet",
                        detail: "Swipe a video left, or select several and download them "
                            + "together. Finished files land here, and in Files under "
                            + "On My iPhone → YT Scraper."
                    )
                } else {
                    lists
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
        // A scan rather than an index, so it has to be re-run to stay honest. Once on
        // appearance, and again whenever the app comes back to the front: these files
        // are deliberately reachable from Files.app, and deleting one there is a normal
        // thing to do. Coming back to a row that no longer has a file behind it would
        // otherwise only fail at the point of tapping it.
        .task { model.localFiles.reload() }
        .onChange(of: phase) { _, new in
            if new == .active { model.localFiles.reload() }
        }
    }

    private var lists: some View {
        List {
            if !model.downloads.jobs.isEmpty {
                Section {
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
                } header: {
                    header("Transfers")
                }
            }

            if !model.localFiles.isEmpty {
                Section {
                    ForEach(model.localFiles.files) { file in
                        FileRow(file: file)
                            .listRowBackground(Color.card)
                            .contentShape(Rectangle())
                            .onTapGesture { model.play(file) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    model.localFiles.delete(file)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    sharing = file.url
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(Color.secondaryText)
                            }
                    }
                } header: {
                    header("On this phone")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .textCase(nil)
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

/// One file on disk: tap it to play.
struct FileRow: View {
    let file: LocalFile

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Artwork(url: file.artwork,
                        icon: file.kind == .audio ? "waveform" : "film",
                        width: 84, height: 48)
                Image(systemName: "play.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(file.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(2)

                Text(file.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if file.kind == .audio {
                Image(systemName: "headphones")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Play \(file.title)")
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
