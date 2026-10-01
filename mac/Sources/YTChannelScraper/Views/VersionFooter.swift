import SwiftUI

/// The version, in the quietest place a window has.
///
/// An update is worth knowing about and is almost never worth interrupting for, and a red
/// pill in the chrome gets that balance the wrong way round — it is loud every time you
/// open the app and says nothing the rest of the time. A line at the foot of the window is
/// the opposite: it is the version number when there is nothing to say, and the same line
/// says there is something when there is.
struct VersionFooter: View {
    @Bindable var updater: AppUpdater
    /// The Downloads panel rises out of this footer, so its switch lives here, on the
    /// edge it opens from — and the footer never hides, unlike the header row.
    @Bindable var downloader: Downloader
    var downloadsOpen = false
    var toggleDownloads: () -> Void = {}
    /// A video is open in the player, so there is a list under it to fold away.
    var playerOpen = false
    @State private var hovering = false
    @State private var hoveringPlayer = false
    /// See `PreviewPanel.theatre`. Here because the footer stays put whichever way it is
    /// set, so the switch never hides itself.
    @AppStorage("player.theatre") private var theatre = false

    var body: some View {
        HStack(spacing: 0) {
            DownloadsItem(downloader: downloader, isOn: downloadsOpen, toggle: toggleDownloads)

            Spacer(minLength: 0)

            Button(action: open) {
                HStack(spacing: 6) {
                    if updater.updateAvailable != nil {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 5, height: 5)
                    }
                    Text(label)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(hovering ? .primary : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .pointingHand()
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)

            // At the right-hand end, under the title bar's chevron that folds the search
            // bar: the two switches that make room for the picture sit on one side.
            if playerOpen {
                Rectangle()
                    .fill(Palette.ink(0.18))
                    .frame(width: 1, height: 10)
                    .padding(.horizontal, 10)
                Button { withAnimation(PreviewPanel.fold) { theatre.toggle() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: theatre ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                        Text(theatre ? "Show list" : "Hide list")
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(hoveringPlayer ? .primary : .secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(theatre ? "Show the player's bar and the list under it  (⌥⌘P)"
                              : "Hide everything under the picture, so it has the whole page  (⌥⌘P)")
                .pointingHand()
                .onHover { hoveringPlayer = $0 }
                .animation(.easeOut(duration: 0.14), value: hoveringPlayer)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background {
            if Theme.active.id == .classic { Rectangle().fill(.bar) } else { Palette.ground }
        }
        .overlay(alignment: .top) {
            if Theme.active.id == .classic {
                Divider()
            } else {
                Rectangle().fill(Theme.active.edgeTint.opacity(0.35)).frame(height: 1)
            }
        }
    }

    private var label: String {
        if let release = updater.updateAvailable {
            return "Update to \(release.version) available"
        }
        if case .checking = updater.state { return "Checking for updates…" }
        return updater.current.isEmpty ? "Check for updates" : "Version \(updater.current)"
    }

    private var help: String {
        updater.updateAvailable == nil
            ? "Check for updates"
            : "See what's in this version and install it"
    }

    /// Already found means show it; otherwise go and look, and report either way — a
    /// click asking about updates is owed an answer even when the answer is "none".
    private func open() {
        if updater.updateAvailable != nil {
            updater.showResult()
        } else {
            Task { await updater.check(announce: true) }
        }
    }
}

/// "Downloads", and while anything is queued or running, how many and how far along —
/// a live line rather than the 5pt dot the pill's icon had room for.
private struct DownloadsItem: View {
    @Bindable var downloader: Downloader
    let isOn: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let active = downloader.jobs.filter { !$0.state.isFinished }
        Button(action: toggle) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(active.isEmpty ? "Downloads" : "Downloads · \(active.count) running")
                    .font(.system(size: 10.5).monospacedDigit())
                if !active.isEmpty {
                    // The average across what is still going: one bar for the whole
                    // queue, since the panel above has each one's own.
                    let done = active.map(\.percent).reduce(0, +) / Double(active.count)
                    ProgressView(value: min(max(done, 0), 100), total: 100)
                        .progressViewStyle(.linear)
                        .tint(Palette.accent)
                        .controlSize(.mini)
                        .frame(width: 46)
                }
                Image(systemName: isOn ? "chevron.down" : "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(isOn || hovering ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(isOn ? "Close" : "Open") Downloads  (⌘2)")
        .accessibilityLabel(active.isEmpty ? "Downloads" : "Downloads, \(active.count) running")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .pointingHand()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
