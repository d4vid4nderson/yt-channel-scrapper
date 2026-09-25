import SwiftUI

/// The download control in the player's toolbar.
///
/// One button carrying four meanings, because the thing it acts on has four states and
/// a separate control for each would be three controls too many in a toolbar. It reads
/// the job rather than being told what to draw, so it cannot disagree with the queue.
///
///   nothing yet  →  outlined circle, arrow down      →  tap starts the download
///   running      →  red ring tracking progress,      →  tap pauses
///                   the arrow drifting downwards
///   paused       →  ring holds where it stopped      →  tap resumes
///   done         →  circle filled red, a tick        →  tap opens the downloads
struct DownloadButton: View {
    /// The job for this video, if one has been queued.
    let job: DownloadJob?
    let action: () -> Void

    /// Drives the mux spinner. One `@State` toggled once on appear, because a
    /// repeating animation needs a value to animate *to*.
    @State private var drifting = false

    private var state: DownloadJob.State? { job?.state }

    private var isRunning: Bool {
        state == .downloading || state == .queued || state == .retrying
    }
    private var isDone: Bool { state == .done }

    /// `processing` is the mux, which reports no percentage — the ring sits full while
    /// it happens rather than dropping back to zero.
    private var progress: Double {
        guard let job else { return 0 }
        if job.state == .processing || job.state == .done { return 1 }
        // A hair of ring at zero, so starting a download looks like something happened
        // even before the first bytes land.
        return max(0.03, min(job.percent, 1))
    }

    /// Shown inside the ring while running. Queued reads as "0%", which is honest —
    /// it is waiting for a slot, and pretending otherwise would be worse.
    private var percentText: String {
        guard let job else { return "0%" }
        if job.state == .processing { return "99%" }
        return "\(Int((job.percent * 100).rounded()))%"
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Palette.ink(0.28), lineWidth: 2)

                if isDone {
                    Circle().fill(Palette.accent)
                } else if job != nil, state != .failed, state != .cancelled {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Palette.accent,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        // Trim starts at three o'clock; a progress ring should start at
                        // the top.
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }

                icon
            }
            .frame(width: 28, height: 28)
            .tappable()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onAppear { drifting = true }
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.onFill)
                .transition(.scale.combined(with: .opacity))

        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.accent)

        case .processing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.accent)
                .rotationEffect(.degrees(drifting ? 360 : 0))
                .animation(.linear(duration: 1.4).repeatForever(autoreverses: false),
                           value: drifting)

        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.accent)

        case .some(let running) where !running.isFinished:
            // The number, not a moving arrow. A ring alone is only readable to about a
            // quarter turn, and something that bounces forever reads as decoration
            // rather than as information about a thing that is actually progressing.
            Text(percentText)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.ink(1))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: percentText)

        default:
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink(1))
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .done:        "Downloaded. Open downloads"
        case .paused:      "Paused. Resume download"
        case .processing:  "Processing"
        case .failed:      "Download failed. Try again"
        case .some(let running) where !running.isFinished: "Downloading. Pause"
        default:           "Download"
        }
    }
}
