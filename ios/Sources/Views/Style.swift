import SwiftUI

/// What the phone adds to the shared `Palette`.
///
/// `Views/Palette.swift` comes over from the Mac unchanged and carries the brand: the
/// red accent, the near-black ground, the surfaces. What it cannot carry is anything
/// sized for a pointer. A 24pt checkbox and a hover state are fine with a cursor on them
/// and useless under a thumb, so the metrics below are the phone's own, and every
/// tappable thing is built to Apple's 44pt minimum.
enum Metrics {
    /// Apple's minimum comfortable target. Rows are taller; icon buttons are exactly it.
    static let tap: CGFloat = 44
    static let gutter: CGFloat = 16
    static let corner: CGFloat = 12
    /// A 16:9 thumbnail at the width a phone row can spare.
    static let thumbWidth: CGFloat = 124
    static let thumbHeight: CGFloat = 70
}

extension Color {
    /// Text on the dark ground: full strength for titles, dimmed for the metadata line.
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.58)
    static let hairline = Color.white.opacity(0.10)
    /// A card sitting on the ground — rows, headers, the downloads panel.
    static let card = Color(red: 0.094, green: 0.094, blue: 0.094)
}

/// The dark ground the whole app sits on, ignoring safe areas so it reaches the edges.
struct Ground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Palette.ground.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}

extension View {
    func ground() -> some View { modifier(Ground()) }

    /// A tap target that is at least `Metrics.tap` in both directions without changing
    /// how the content itself is drawn.
    func tappable() -> some View {
        frame(minWidth: Metrics.tap, minHeight: Metrics.tap)
            .contentShape(Rectangle())
    }
}

/// A channel's initials on a coloured disc, for the channels that have no picture.
///
/// Ported from the Mac's `ChannelRow`. The colour is derived from the id rather than
/// from `hashValue`, which is seeded per process and would repaint every channel on
/// every launch — `Channel.hue` does that part.
struct Monogram: View {
    let channel: Channel
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Color(hue: channel.hue, saturation: 0.55, brightness: 0.62))
            .overlay(
                Text(channel.monogram)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}

/// A channel's avatar, falling back to its initials.
struct Avatar: View {
    let channel: Channel
    var size: CGFloat = 44

    var body: some View {
        AsyncImage(url: channel.avatar) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Monogram(channel: channel, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// A video thumbnail with its duration in the corner, the way YouTube draws one.
struct Thumbnail: View {
    let video: Video
    var width: CGFloat = Metrics.thumbWidth
    var height: CGFloat = Metrics.thumbHeight

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: video.thumbnail) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .frame(width: width, height: height)
            .clipped()

            if !video.durationText.isEmpty {
                Text(video.durationText)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// The empty state shared by every list.
struct Placeholder: View {
    let icon: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.secondaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.primaryText)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
