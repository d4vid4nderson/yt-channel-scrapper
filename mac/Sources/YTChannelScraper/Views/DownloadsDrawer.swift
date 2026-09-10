import SwiftUI
import AppKit

/// Downloads come up as a drawer from the bottom edge, over a dimmed page — the way the
/// web app did it. A side column would have cut the header band in half and stolen width
/// from the list; the drawer sits over the top and gives it all back on dismissal.
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

        return GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .opacity(isPresented ? 1 : 0)
                    .onTapGesture(perform: close)

                // Both views stay mounted and the sheet's offset is animated, rather
                // than relying on an insertion transition: an offset is guaranteed to
                // run in both directions, so it slides down on close as well as up.
                sheet(jobs: jobs, hasFinished: hasFinished)
                    .frame(maxWidth: 760)
                    .frame(maxHeight: geo.size.height * 0.72, alignment: .bottom)
                    .offset(y: isPresented ? 0 : geo.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(isPresented)
        .animation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.32), value: isPresented)
        .onExitCommand(perform: close)
    }

    private func sheet(jobs: [DownloadJob], hasFinished: Bool) -> some View {
        VStack(spacing: 0) {
            head(count: jobs.count, hasFinished: hasFinished)
            Divider().overlay(.white.opacity(0.09))
            jobList(jobs)
            Divider().overlay(.white.opacity(0.09))
            UpdaterFooter(updater: updater)
        }
        .background(Palette.sheetSurface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                .strokeBorder(Color(white: 0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 35, y: -8)
    }

    private func head(count: Int, hasFinished: Bool) -> some View {
        HStack(spacing: 12) {
            Text("Downloads")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Color(white: 0.78))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.09), in: Capsule())
            }

            Spacer()

            SheetButton(title: "Open Folder", icon: "folder") {
                NSWorkspace.shared.open(Paths.downloads)
            }
            SheetButton(title: "Clear", icon: "xmark.bin") {
                downloader.clearFinished()
            }
            .disabled(!hasFinished)
            .opacity(hasFinished ? 1 : 0.4)
            SheetButton(title: "Close", icon: "xmark", action: close)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func jobList(_ jobs: [DownloadJob]) -> some View {
        if jobs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(white: 0.55))
                Text("No downloads yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.78))
                Text("Pick some videos and they will show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 54)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(jobs) { job in
                        JobRow(job: job) { downloader.remove(job) }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
    }
}

/// The sheet's own button style: light on the dark surface, never the system pill which
/// would repaint white-on-white here.
private struct SheetButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.white.opacity(hovering ? 0.22 : 0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .pointingHand()
        .onHover { hovering = $0 }
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
                    .foregroundStyle(.white)
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
                            .foregroundStyle(Color(white: 0.62))
                    }
                    if let error = job.error, job.state == .failed || job.state == .retrying {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(job.state == .failed ? Palette.accent : Color(white: 0.62))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            if job.state == .done, let file = job.file {
                SheetButton(title: "Show in Finder", icon: "magnifyingglass") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
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
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
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
        case .retrying:    "arrow.triangle.2.circlepath"
        case .processing:  "gearshape"
        case .done:        "checkmark.circle.fill"
        case .failed:      "exclamationmark.triangle.fill"
        case .cancelled:   "slash.circle"
        }
    }

    private var tint: Color {
        switch job.state {
        case .done:     Color(red: 0.35, green: 0.82, blue: 0.45)
        case .failed:   Palette.accent
        case .retrying: .orange
        default:        Color(white: 0.72)
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
                        .foregroundStyle(Color(white: 0.72))
                    Text(updater.current.isEmpty ? "…" : updater.current)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Color(white: 0.55))
                    if updater.isUsingDownloadedCopy {
                        Text("updated")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(white: 0.62))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.1), in: Capsule())
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
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .unknown:
            EmptyView()
        case .checking:
            note("Checking…", Color(white: 0.55))
        case .upToDate:
            note("Up to date", Color(white: 0.55))
        case .available(let version):
            note("\(version) available", Color(red: 1, green: 0.72, blue: 0.35))
        case .downloading:
            note("Downloading…", Color(white: 0.55))
        case .installing:
            note("Installing…", Color(white: 0.55))
        case .installed(let version):
            note("Updated to \(version) — in use now", Color(red: 0.4, green: 0.85, blue: 0.5))
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

private struct FooterButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    prominent
                        ? AnyShapeStyle(Palette.accent.opacity(hovering ? 0.85 : 1))
                        : AnyShapeStyle(Color.white.opacity(hovering ? 0.22 : 0.1)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .help(prominent
              ? "Download the newer yt-dlp and use it from the next download on"
              : "See whether a newer yt-dlp has been released")
        .pointingHand()
        .onHover { hovering = $0 }
    }
}
