import SwiftUI

/// The shape of a list that has not arrived yet.
///
/// Opening a channel used to empty the page, and an empty page is the landing screen —
/// so asking for a channel took you away from the results you were reading and dropped
/// you back at the hero for a second or two. These rows are what stands there instead:
/// the page keeps its header, its bar and its scroll position, and the list underneath
/// is drawn as the cards it is about to become.
///
/// They are deliberately dumb — grey bars in the real rows' geometry, nothing that reads
/// as content. A skeleton that guesses at titles is a skeleton you have to read twice.

// MARK: - The lists

/// Stand-ins for a channel's videos. Six rows: enough to fill the visible list at the
/// window's minimum height, so the page looks loaded rather than half empty.
struct VideoListSkeleton: View {
    /// How much of the title line to leave blank — titles are not all one length, and six
    /// bars cut to the same width read as a barcode rather than a list.
    private let gaps: [CGFloat] = [150, 320, 90, 240, 60, 190]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { index in
                SkeletonCard(minHeight: 90) {
                    Bone(corner: 4.4).frame(width: 17, height: 17)
                    Bone(corner: 10).frame(width: 124, height: 124 * 9 / 16)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 0) {
                            Bone().frame(height: 12)
                            Color.clear.frame(width: gaps[index])
                        }
                        Bone().frame(width: 84, height: 9)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Stand-ins for a search's channels. Four, because a search answers with one page and
/// the eye only needs enough of it to know what is coming.
struct ChannelListSkeleton: View {
    private let gaps: [CGFloat] = [260, 140, 330, 200]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                SkeletonCard(minHeight: 84, verticalPadding: 12) {
                    Circle()
                        .fill(Palette.ink(0.09))
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 0) {
                            Bone().frame(height: 12)
                            Color.clear.frame(width: gaps[index])
                        }
                        Bone().frame(width: 96, height: 9)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Parts

/// The card both rows are drawn on: the resting state of `VideoRow` and `ChannelRow`,
/// with nothing in it. Same corner, same hairline, same shadow — so when the real rows
/// land they arrive in place rather than replacing something differently shaped.
private struct SkeletonCard<Content: View>: View {
    let minHeight: CGFloat
    var verticalPadding: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) {
            content
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, verticalPadding)
        .frame(minHeight: minHeight)
        .background(Palette.rowPlate)
        .clipShape(ThemedRect(cornerRadius: 14, style: .continuous))
        .overlay {
            ThemedRect(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.ink(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }
}

/// One grey bar, with a light travelling across it.
///
/// The sweep is an offset rather than an animated gradient because only the offset is a
/// thing SwiftUI can interpolate — stops computed from state would step once and sit
/// still. Every bone starts its loop when the list mounts, and they all mount together,
/// so the whole column moves as one.
private struct Bone: View {
    var corner: CGFloat = 5
    @State private var swept = false

    private var shape: ThemedRect { ThemedRect(cornerRadius: corner, style: .continuous) }

    var body: some View {
        shape
            .fill(Palette.ink(0.10))
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        colors: [.clear, Palette.ink(0.13), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(width * 0.55, 40))
                    .offset(x: swept ? width : -max(width * 0.55, 40))
                }
                .clipShape(shape)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.15).delay(0.1).repeatForever(autoreverses: false)) {
                    swept = true
                }
            }
    }
}
