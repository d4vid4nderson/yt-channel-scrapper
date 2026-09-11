import AppKit
import SwiftUI

/// What the app says about its own updates.
///
/// One sheet for every answer — found, not found, downloading, failed — because a check
/// the user asked for owes a reply in the place they asked it, and switching surfaces
/// between "there is one" and "there isn't" is how an app ends up with two update UIs.
struct AppUpdateSheet: View {
    @Bindable var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            body(for: updater.state)
            footer(for: updater.state)
        }
        .frame(width: 460)
        .background(Palette.sheetSurface)
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandMark(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("YT Channel Scraper")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(updater.current.isEmpty ? "Installed version unknown" : "Version \(updater.current)")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func body(for state: AppUpdater.State) -> some View {
        switch state {
        case .idle, .checking:
            line {
                ProgressView().controlSize(.small).tint(.white)
                Text("Looking for a newer version…")
            }

        case .upToDate:
            line {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.35, green: 0.82, blue: 0.45))
                Text("This is the latest version.")
            }

        case .available(let release):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Text("Version \(release.version)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    if let published = release.published {
                        Text(published.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
                if release.notes.isEmpty {
                    Text("No release notes.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    ScrollView {
                        Text(notes(release.notes))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.72))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 210)
                }
            }
            .padding(.horizontal, 22)

        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 9) {
                Text("Downloading…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.78))
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Palette.accent)
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 22)

        case .installing:
            line {
                ProgressView().controlSize(.small).tint(.white)
                Text("Replacing the app…")
            }

        case .relaunching:
            line {
                ProgressView().controlSize(.small).tint(.white)
                Text("Reopening the new version…")
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("You can always download it yourself from the releases page.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.40))
            }
            .padding(.horizontal, 22)
        }
    }

    @ViewBuilder
    private func footer(for state: AppUpdater.State) -> some View {
        HStack(spacing: 9) {
            Button("Releases…") {
                NSWorkspace.shared.open(AppUpdater.releasesPage)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.42))
            .help("Open the releases page in your browser")
            .pointingHand()

            Spacer(minLength: 0)

            switch state {
            case .available:
                UpdateButton(title: "Later") { updater.dismissResult() }
                UpdateButton(title: "Update and Relaunch", prominent: true) {
                    Task { await updater.install() }
                }
            case .downloading, .installing, .relaunching:
                // Nothing to press: the swap is atomic and cancelling halfway is a way to
                // end up with neither version.
                EmptyView()
            default:
                UpdateButton(title: "Done") { updater.dismissResult() }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    private func line<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 9) {
            content()
        }
        .font(.system(size: 12.5))
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 22)
    }

    /// GitHub hands back markdown. Rendered where it can be, shown as written where it
    /// cannot — release notes are worth reading either way.
    private func notes(_ markdown: String) -> AttributedString {
        // Inline-only rendering handles bold and code but leaves block syntax as written,
        // so the heading markers are taken off first rather than shown to the reader.
        let cleaned = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                var text = line
                while text.hasPrefix("#") { text = text.dropFirst() }
                return text.hasPrefix(" ") ? text.dropFirst() : text
            }
            .joined(separator: "\n")
        return (try? AttributedString(
            markdown: cleaned,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(cleaned)
    }
}

private struct UpdateButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: prominent ? .semibold : .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    prominent
                        ? AnyShapeStyle(Palette.accent.opacity(hovering ? 0.85 : 1))
                        : AnyShapeStyle(Color.white.opacity(hovering ? 0.2 : 0.1)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { hovering = $0 }
    }
}
