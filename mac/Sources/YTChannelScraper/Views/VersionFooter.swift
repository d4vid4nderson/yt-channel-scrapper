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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
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
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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
