import SwiftUI

/// One video as a card, the way the web app drew it: hairline border, hover lift, and a
/// dark red-bloomed surface once picked.
struct VideoRow: View {
    let video: Video
    let isPicked: Bool
    let toggle: () -> Void
    let downloadOne: () -> Void
    let preview: () -> Void

    @State private var hovering = false
    @State private var hoveringThumb = false

    private let corner: CGFloat = 14
    private let rowHeight: CGFloat = 90

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggle) {
                CheckBox(isOn: isPicked, onDarkSurface: isPicked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(video.title)
            .accessibilityAddTraits(isPicked ? [.isSelected] : [])
            .help(isPicked ? "Untick this video" : "Tick this video to download it")
            .pointingHand()

            // The thumbnail plays; the rest of the row picks. Keeping them apart means
            // watching something does not disturb a selection already made.
            Button(action: preview) { thumbnail }
                .buttonStyle(.plain)
                .help("Preview this video")
                .pointingHand()

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(isPicked ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(video.viewsText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(isPicked ? Color(white: 0.70) : .secondary)
            }

            Spacer(minLength: 8)

            // Only picked rows offer it, matching `.item.sel .row-dl { display: grid }`.
            if isPicked {
                RowDownloadButton(action: downloadOne)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: rowHeight)
        .background {
            if isPicked {
                Palette.pickedSurface(height: rowHeight)
            } else {
                Color(nsColor: .controlBackgroundColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .shadow(color: shadowColor, radius: hovering ? 9 : 6, y: hovering ? 5 : 3)
        .offset(y: hovering ? -1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.18), value: isPicked)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
        .pointingHand()
    }

    private var borderColor: Color {
        if isPicked {
            return hovering
                ? Color(red: 0.29, green: 0.13, blue: 0.15)
                : Color(red: 0.20, green: 0.10, blue: 0.11)
        }
        return hovering ? Color.primary.opacity(0.22) : Color.primary.opacity(0.12)
    }

    private var shadowColor: Color {
        isPicked
            ? Palette.accent.opacity(hovering ? 0.28 : 0.20)
            : .black.opacity(hovering ? 0.10 : 0.05)
    }

    private var thumbnail: some View {
        AsyncImage(url: video.thumbnail) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 124, height: 124 * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if hoveringThumb {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(systemName: "play.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .onHover { hoveringThumb = $0 }
        .animation(.easeOut(duration: 0.12), value: hoveringThumb)
        .overlay(alignment: .bottomTrailing) {
            if !video.durationText.isEmpty {
                // Duration sits on the thumbnail the way it does on YouTube, not in the
                // metadata line.
                Text(video.durationText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
        }
    }
}

/// The red disc that appears on a picked row to fetch just that one video.
private struct RowDownloadButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(hovering ? Color(red: 1, green: 0.13, blue: 0.2) : Palette.accent)
                )
                .shadow(color: Palette.accent.opacity(hovering ? 0.65 : 0), radius: 8)
                .scaleEffect(hovering ? 1.1 : 1)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 2)
        .help("Download just this video")
        .pointingHand()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
