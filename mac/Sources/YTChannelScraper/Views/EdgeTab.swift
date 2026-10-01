import SwiftUI

/// A panel's handle, pinned to the edge of the page its panel slides out from: Saved on
/// the left, Family on the right, Downloads along the bottom.
///
/// These used to be buttons in the window's toolbar, and later moved into the header row
/// once a channel was open — so they were in a different place depending on where you
/// were. A handle on the edge is where the panel itself is, never moves between views, and
/// rides the panel's edge as it opens, so the same tab that opened it is the one that puts
/// it away. The chevron points the way the click will move the panel.
struct EdgeTab: View {
    enum Edge { case leading, trailing, bottom }

    let edge: Edge
    let icon: String
    /// For the tooltip and VoiceOver; the tab itself is the icon alone.
    let title: String
    let shortcut: String
    var busy = false
    let isOpen: Bool
    let toggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            stack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .overlay(alignment: .topTrailing) {
                        if busy {
                            Circle()
                                .fill(isOpen ? Palette.onFill : Palette.accent)
                                .frame(width: 5, height: 5)
                                .offset(x: 3, y: -2)
                        }
                    }
                Image(systemName: chevron)
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(isOpen ? Palette.onFill : Palette.ink(hovering ? 0.95 : 0.7))
            .frame(width: size.width, height: size.height)
            .background {
                if isOpen {
                    ThemedRect(cornerRadius: 7, style: .continuous).fill(Palette.accent)
                } else {
                    Palette.sheetSurface
                        .clipShape(ThemedRect(cornerRadius: 7, style: .continuous))
                }
            }
            .overlay {
                ThemedRect(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.ink(hovering || isOpen ? 0.3 : 0.16), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(isOpen ? "Close" : "Open") \(title)  (\(shortcut))")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .onHover { hovering = $0 }
        .pointingHand()
        .padding(padding)
    }

    private var size: CGSize {
        edge == .bottom ? CGSize(width: 54, height: 22) : CGSize(width: 22, height: 54)
    }

    /// Off the very edge by a hair, so the outline reads against the window border.
    private var padding: EdgeInsets {
        switch edge {
        case .leading:  EdgeInsets(top: 0, leading: 3, bottom: 0, trailing: 0)
        case .trailing: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 3)
        case .bottom:   EdgeInsets(top: 0, leading: 0, bottom: 3, trailing: 0)
        }
    }

    /// Which way the panel will move: out from its edge when closed, back into it when open.
    private var chevron: String {
        switch (edge, isOpen) {
        case (.leading, false), (.trailing, true): "chevron.right"
        case (.leading, true), (.trailing, false): "chevron.left"
        case (.bottom, false): "chevron.up"
        case (.bottom, true):  "chevron.down"
        }
    }

    @ViewBuilder
    private func stack(@ViewBuilder _ content: () -> some View) -> some View {
        if edge == .bottom {
            HStack(spacing: 5, content: content)
        } else {
            VStack(spacing: 5, content: content)
        }
    }
}
