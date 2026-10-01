import SwiftUI

/// Which edge a drawer lives on. A file-scope enum rather than one nested in the generic
/// view, so the two drawers can name a side without naming a content type.
enum DrawerSide {
    case leading, trailing

    /// The seam faces the page.
    var innerEdge: Alignment { self == .leading ? .trailing : .leading }
}

/// A favourites panel: the surface, the seam, and nothing about how it arrives. Where it
/// sits and how it opens is the page's business — see `drawerSlot`.
///
/// It takes room from the page rather than covering it. A panel over the top has to dim
/// what it hides, and then the list you were reading is both there and unusable; a panel
/// beside it leaves that list working, which is the whole reason to have your saved
/// channels open while you look at a channel.
struct SideDrawer<Content: View>: View {
    let side: DrawerSide
    @Binding var isPresented: Bool
    let content: Content

    init(
        side: DrawerSide,
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.side = side
        self._isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        content
            .padding(.top, 16)
            .frame(width: Layout.drawerWidth)
            .frame(maxHeight: .infinity)
            .background(Palette.sheetSurface)
            // A hairline, not a shadow: the slot clips to its own width, and a shadow
            // cast across that boundary would be sheared off at the seam anyway.
            .overlay(alignment: side.innerEdge) {
                Rectangle()
                    .fill(Palette.ink(0.2))
                    .frame(width: 1)
            }
            .onExitCommand { isPresented = false }
    }
}

extension View {
    /// Hold a panel in a slot that opens from `width` to nothing, taking the page with it.
    ///
    /// The panel is laid out at its full width throughout and the *slot* is what changes
    /// size, so the text inside never reflows mid-animation. Anchoring the panel to the
    /// slot's inner edge is what turns a widening box into a panel sliding in from the
    /// window's edge rather than a curtain being drawn across one.
    func drawerSlot(open: Bool, side: DrawerSide) -> some View {
        frame(width: Layout.drawerWidth)
            .frame(width: open ? Layout.drawerWidth : 0, alignment: side.innerEdge)
            .clipped()
    }
}

/// The drawers' own button: light on the dark surface, never the system pill, which would
/// repaint white-on-white here.
///
/// The same square plate as every icon button in the window's bars (`ChromeButtonStyle`),
/// rather than the disc it was: the player's bar, the toolbars and the panels each had
/// their own idea of what an icon button looked like, and three shapes for one job is
/// what made the window feel assembled rather than designed.
struct SheetButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.chrome(.secondary, square: true))
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The small dark disc that drops something from the library — a saved channel off the
/// left panel, a saved video off the right one.
struct RemoveButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(Palette.ink(hovering ? 1 : 0.7))
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(hovering ? Palette.accent : Palette.ink(0.22))
                )
                .overlay {
                    Circle().strokeBorder(Palette.ink(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
