import SwiftUI

/// One video as a card, the way the web app drew it: hairline border, hover lift, and a
/// dark red-bloomed surface once picked.
struct VideoRow: View {
    let video: Video
    let isPicked: Bool
    let isSaved: Bool
    /// Whether this row is being shown in the saved list rather than a channel's.
    ///
    /// Two things follow. That list mixes channels, so the row has to say which one this
    /// is; and every row in it is kept, so marking them all as kept would say nothing —
    /// the list itself is already the statement. The keeping treatment is for a row that
    /// stands out *from its neighbours*.
    var inSavedList = false
    let toggle: () -> Void
    let downloadOne: () -> Void
    /// The thumbnail's play: into the player at the top, like the title.
    let preview: () -> Void
    /// The title's link: the player at the top of the page.
    var openCard: (() -> Void)? = nil
    let toggleSaved: () -> Void

    /// The ⋯ that puts this video on a child's shelf, or nothing when there is no family
    /// set up. Held as a view rather than as another handful of closures: the menu needs
    /// the roster, the current state and two actions, and passing four more parameters to
    /// say "show a menu" is worse than passing the menu.
    var shelfMenu: ShelfMenu?

    @State private var hovering = false
    @State private var hoveringThumb = false

    private let corner: CGFloat = 14
    private let rowHeight: CGFloat = 72

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggle) {
                CheckBox(isOn: isPicked, onPickedSurface: isPicked)
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
                .help("Play this video")
                .pointingHand()

            VStack(alignment: .leading, spacing: 4) {
                TitleLink(title: video.title, isPicked: isPicked, open: openCard)
                Text(video.metaText(showingChannel: inSavedList))
                    .font(.system(size: 11.5))
                    .foregroundStyle(isPicked ? Palette.ink(0.70) : .secondary)
            }

            Spacer(minLength: 8)

            // Same rule as the save mark below: an always-visible menu on every row is
            // clutter, and the row under the cursor is the one being considered.
            //
            // Both are always laid out and only faded in, so the title's width never
            // changes under the pointer — inserting them on hover narrowed it and the
            // title re-wrapped every time the cursor crossed a row.
            if let shelfMenu {
                shelfMenu
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
            }

            // Keeping a video is a quieter act than picking one to download, so the mark
            // only shows for the row under the cursor — or for one already kept.
            SaveMark(
                isSaved: isSaved,
                size: 15,
                noun: "video",
                onPickedSurface: isPicked,
                action: toggleSaved
            )
            .opacity(hovering || isSaved ? 1 : 0)
            .allowsHitTesting(hovering || isSaved)

            // Only picked rows offer it, matching `.item.sel .row-dl { display: grid }`.
            if isPicked {
                RowDownloadButton(action: downloadOne)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: rowHeight)
        .background {
            if isPicked {
                Palette.pickedSurface(height: rowHeight)
            } else if marksSaved {
                Palette.savedSurface(height: rowHeight)
            } else {
                Palette.rowPlate
            }
        }
        .clipShape(ThemedRect(cornerRadius: corner, style: .continuous))
        .overlay {
            ThemedRect(cornerRadius: corner, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .themeEdge(radius: corner, lit: isPicked || hovering)
        .shadow(color: shadowColor, radius: hovering ? 9 : 6, y: hovering ? 5 : 3)
        .offset(y: hovering ? -1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.18), value: isPicked)
        .animation(.easeOut(duration: 0.22), value: isSaved)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
        .pointingHand()
    }

    private var marksSaved: Bool { isSaved && !inSavedList }

    private var borderColor: Color {
        if isPicked {
            return Palette.pickedEdge(hot: hovering)
        }
        if marksSaved {
            return Palette.accent.opacity(hovering ? 0.5 : 0.32)
        }
        return hovering ? Palette.ink(0.22) : Palette.ink(0.12)
    }

    private var shadowColor: Color {
        if isPicked { return Palette.accent.opacity(hovering ? 0.28 : 0.20) }
        if marksSaved { return Palette.accent.opacity(hovering ? 0.22 : 0.14) }
        return .black.opacity(hovering ? 0.10 : 0.05)
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
        .frame(width: 104, height: 104 * 9 / 16)
        .clipShape(ThemedRect(cornerRadius: 10, style: .continuous))
        .overlay {
            if hoveringThumb {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(systemName: "play.fill")
                        .font(.system(size: 15))
                        // White on the black scrim, as the duration is: a theme's onFill
                        // can be near-black, and this sat invisible on the Nostromo.
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
                .clipShape(ThemedRect(cornerRadius: 10, style: .continuous))
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
                    // White on the scrim in every theme: the scrim is black over a
                    // photograph, and a theme's onFill can be near-black.
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.8), in: ThemedRect(cornerRadius: 4))
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
                .foregroundStyle(Palette.onFill)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(hovering ? Palette.accentHot : Palette.accent)
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

/// A video's title, which opens it in the player at the top — underlined under the pointer,
/// so it reads as the link it is. Without `open`, plain text.
private struct TitleLink: View {
    let title: String
    let isPicked: Bool
    let open: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let linked = hovering && open != nil
        let text = Text(title)
            .font(.system(size: 13.5, weight: .medium))
            .underline(linked, color: Palette.accent)
            .foregroundStyle(linked ? Palette.accent : (isPicked ? Palette.ink(1) : Palette.ink(0.95)))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        if let open {
            text
                .onTapGesture(perform: open)
                .onHover { hovering = $0 }
                .help("Open the player")
                .pointingHand()
        } else {
            text
        }
    }
}
