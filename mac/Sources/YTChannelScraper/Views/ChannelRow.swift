import SwiftUI

/// A channel's picture, or its initials when there isn't one.
///
/// Two of the three ways a channel gets here carry no avatar — a channel saved from a
/// scrape and a row imported from Takeout both know only an id and a name — so the
/// fallback is the common case, not the error case, and is drawn to look deliberate.
struct ChannelAvatar: View {
    let channel: Channel
    var size: CGFloat = 56

    var body: some View {
        AsyncImage(url: channel.avatar) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    private var monogram: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: channel.hue, saturation: 0.50, brightness: 0.64),
                    Color(hue: channel.hue, saturation: 0.60, brightness: 0.42),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(channel.monogram)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// The mark that keeps a channel or a video. Filled and red once saved, matching the
/// accent the rest of the app uses for "this one is picked".
///
/// A bookmark rather than a star: a star is a rating, and this is not one — nothing here
/// is being scored, it is being put somewhere to come back to. A bookmark says that, and
/// says it without colliding with the red download arrow two controls along, which is the
/// other thing on the row that means "take this away with me".
struct SaveMark: View {
    let isSaved: Bool
    var size: CGFloat = 17
    /// What this one keeps, for the tooltip — the same control serves both lists.
    var noun = "channel"
    /// On a dark surface an outline mark in `.secondary` all but vanishes.
    var onDarkSurface = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                // Two shadows, not one: a tight core and a wide falloff. A single
                // shadow at this radius reads as a smudge behind the mark rather than
                // light coming off it.
                .shadow(color: glow, radius: hovering ? 7 : 5)
                .shadow(color: glow.opacity(0.55), radius: hovering ? 16 : 12)
                .scaleEffect(hovering ? 1.14 : 1)
                .frame(width: size * 1.9, height: size * 1.9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isSaved
              ? "Remove this \(noun) from your saved \(noun)s"
              : "Save this \(noun) to your side panel")
        .accessibilityLabel(isSaved ? "Saved" : "Save \(noun)")
        .pointingHand()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.easeOut(duration: 0.18), value: isSaved)
    }

    /// Only a kept mark gives off light — an empty outline glowing would be saying the
    /// opposite of what it means.
    private var glow: Color {
        isSaved ? Palette.accent.opacity(hovering ? 0.9 : 0.75) : .clear
    }

    private var tint: Color {
        if isSaved { return Palette.accent }
        if onDarkSurface { return .white.opacity(hovering ? 0.95 : 0.6) }
        return hovering ? .primary.opacity(0.75) : .secondary
    }
}

/// One channel as a card — the video card's twin, so a list of channels and a list of
/// videos read as the same app.
struct ChannelRow: View {
    let channel: Channel
    let isSaved: Bool
    let open: () -> Void
    let toggleSaved: () -> Void

    @State private var hovering = false

    private let corner: CGFloat = 14

    var body: some View {
        HStack(spacing: 14) {
            ChannelAvatar(channel: channel)

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                if !channel.subtitle.isEmpty {
                    Text(channel.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Only on hover, the way the video card only shows its download button once
            // the row is picked — the mark is for the row you are looking at.
            if hovering || isSaved {
                SaveMark(isSaved: isSaved, action: toggleSaved)
                    .transition(.opacity)
            }

            Text("Open")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? .white : Color.secondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(hovering ? AnyShapeStyle(Palette.accent)
                                            : AnyShapeStyle(Color.primary.opacity(0.06)))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 84)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(hovering ? Color.primary.opacity(0.22) : Color.primary.opacity(0.12),
                              lineWidth: 1)
        }
        .shadow(color: .black.opacity(hovering ? 0.10 : 0.05), radius: hovering ? 9 : 6,
                y: hovering ? 5 : 3)
        .offset(y: hovering ? -1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help("List this channel's videos")
        .pointingHand()
    }
}
