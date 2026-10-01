import SwiftUI
import AppKit

/// Downloads open along the bottom edge, taking height from the page rather than covering
/// it — so the list you queued from is still in front of you, and still tickable, while
/// the queue runs.
struct DownloadsDrawer: View {
    @Bindable var downloader: Downloader
    @Bindable var updater: Updater
    @Binding var isPresented: Bool

    private func close() { isPresented = false }

    var body: some View {
        // Read up front, in this view's own body. Reads inside a GeometryReader's
        // content closure land in a different update scope, so a job appearing in the
        // list would not necessarily invalidate this view.
        let jobs = downloader.jobs
        let hasFinished = downloader.hasFinished

        return VStack(spacing: 0) {
            head(count: jobs.count, hasFinished: hasFinished)
            Divider().overlay(Palette.ink(0.09))
            jobList(jobs)
            Divider().overlay(Palette.ink(0.09))
            UpdaterFooter(updater: updater)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.sheetSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.ink(0.2))
                .frame(height: 1)
        }
        .onExitCommand(perform: close)
    }

    private func head(count: Int, hasFinished: Bool) -> some View {
        HStack(spacing: 12) {
            Text("Downloads")
                .displayType(15, classic: .medium)
                .foregroundStyle(Palette.ink(1))

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.ink(0.78))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Palette.ink(0.09), in: ThemedCapsule())
            }

            Spacer()

            SheetButton(title: "Open Folder", icon: "folder") {
                NSWorkspace.shared.open(Paths.downloads)
            }
            SheetButton(title: "Clear", icon: "xmark.bin") {
                downloader.clearFinished()
            }
            .disabled(!hasFinished)
            SheetButton(title: "Close", icon: "xmark", action: close)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func jobList(_ jobs: [DownloadJob]) -> some View {
        if jobs.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(Palette.ink(0.55))
                Text("No downloads yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink(0.78))
                Text("Pick some videos and they will show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(jobs) { job in
                        JobRow(job: job) { downloader.remove(job) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }
}

private struct JobRow: View {
    @Bindable var job: DownloadJob
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(job.video.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink(1))
                    .lineLimit(1)

                if job.state == .downloading || job.state == .processing {
                    ProgressView(value: job.percent, total: 100)
                        .progressViewStyle(.linear)
                        .tint(Palette.accent)
                        .frame(height: 4)
                }

                HStack(spacing: 8) {
                    Label(job.state.label, systemImage: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tint)
                    if job.state == .downloading, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Palette.ink(0.62))
                    }
                    if let error = job.error, job.state == .failed || job.state == .retrying {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(job.state == .failed ? Palette.accent : Palette.ink(0.62))
                            .lineLimit(1)
                    }
                    // The mp3 is reported either way once the video is down: silence
                    // would leave "did I get one?" to be answered in Finder.
                    if job.state == .done, job.wantsSidecarAudio {
                        if let audioError = job.audioError {
                            Text("no mp3 — \(audioError)")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.warn)
                                .lineLimit(1)
                        } else if job.audioFile != nil {
                            Text("+ mp3")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.ink(0.62))
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            if job.state == .done, !job.savedFiles.isEmpty {
                SheetButton(title: "Show in Finder", icon: "magnifyingglass") {
                    NSWorkspace.shared.activateFileViewerSelecting(job.savedFiles)
                }
            }
            SheetButton(
                title: job.state.isFinished ? "Remove from list" : "Cancel this download",
                icon: "xmark",
                action: remove
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.ink(0.045), in: ThemedRect(cornerRadius: 14, style: .continuous))
        .overlay {
            ThemedRect(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.ink(0.08), lineWidth: 1)
        }
        .themeEdge(radius: 14)
    }

    private var detail: String {
        [String(format: "%.0f%%", job.percent), job.speedText, job.etaText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var icon: String {
        switch job.state {
        case .queued:      "clock"
        case .downloading: "arrow.down.circle"
        case .paused:      "pause.circle"
        case .retrying:    "arrow.triangle.2.circlepath"
        case .processing:  "gearshape"
        case .done:        "checkmark.circle.fill"
        case .failed:      "exclamationmark.triangle.fill"
        case .cancelled:   "slash.circle"
        }
    }

    private var tint: Color {
        switch job.state {
        case .done:     Palette.good
        case .failed:   Palette.accent
        case .retrying: Palette.warn
        default:        Palette.ink(0.72)
        }
    }
}


/// yt-dlp's version and the way to move it forward.
///
/// It lives in the downloads panel because yt-dlp is what does the downloading — when a
/// download fails because YouTube changed something, this is the thing to reach for.
private struct UpdaterFooter: View {
    @Bindable var updater: Updater

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("yt-dlp")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink(0.72))
                    Text(updater.current.isEmpty ? "…" : updater.current)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Palette.ink(0.55))
                    if updater.isUsingDownloadedCopy {
                        Text("updated")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.ink(0.62))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Palette.ink(0.1), in: ThemedCapsule())
                    }
                }
                status
            }

            Spacer(minLength: 8)

            if case .downloading(let fraction) = updater.state {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Palette.accent)
                    .frame(width: 90)
            } else if updater.canInstall {
                FooterButton(title: "Update", prominent: true) {
                    Task { await updater.install() }
                }
            } else if !updater.isBusy {
                FooterButton(title: "Check for Updates") {
                    Task { await updater.check() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .unknown:
            EmptyView()
        case .checking:
            note("Checking…", Palette.ink(0.55))
        case .upToDate:
            note("Up to date", Palette.ink(0.55))
        case .available(let version):
            note("\(version) available", Palette.warn)
        case .downloading:
            note("Downloading…", Palette.ink(0.55))
        case .installing:
            note("Installing…", Palette.ink(0.55))
        case .installed(let version):
            note("Updated to \(version) — in use now", Palette.good)
        case .failed(let message):
            note(message, Palette.accent)
        }
    }

    private func note(_ text: String, _ colour: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(colour)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The window's own plates (`ChromeButtonStyle`): the primary for Update, a secondary
/// for Check. It drew its own, with on-fill lettering on both — fine on the accent, but
/// on the faint secondary plate that was dark text on a dark panel in a dark theme.
private struct FooterButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.chrome(prominent ? .primary : .secondary))
            .help(prominent
                  ? "Download the newer yt-dlp and use it from the next download on"
                  : "See whether a newer yt-dlp has been released")
    }
}
