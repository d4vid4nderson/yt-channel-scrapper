import SwiftUI

/// The window's control system: one set of heights, corners and fills for every bar in the
/// main window — the header row, the results toolbar, the player's bar and the panels.
///
/// Before this, each bar had grown its own controls. The header's home button was a
/// toolbar toggle about 24pt tall beside a search pill nearly 40pt tall; the tab bar was
/// accent capsules; the controls row was grey capsules of a third height; the player's bar
/// mixed circles, capsules and a filled pill. Nothing was wrong on its own, and together it
/// read as several apps' worth of buttons in one window. The fix is not a new look per bar
/// but one instrument panel: every control in a bar is the same height, the same corner,
/// and lit the same way, so the eye reads the row by what the controls say rather than by
/// what shape each one happens to be.
///
/// Mac only, and deliberately not in `Palette.swift`, which the phone compiles in place.
enum Chrome {
    /// Every control in a toolbar row.
    static let control: CGFloat = 28
    /// The header row's controls, one step up: they lead the window.
    static let large: CGFloat = 32
    /// A toolbar row: a 28pt control and 8pt above and below it.
    static let bar: CGFloat = 44
    /// The header row under the title bar. Was 64, which left a 32pt control floating in
    /// a band twice its height; 52 gives it the same 10pt margin the toolbar rows have.
    static let header: CGFloat = 52

    /// A control's corner at a given height. Seven at 28 and eight at 32 — a quarter of
    /// the height, rounded, so the two sizes look like the same part scaled.
    static func radius(_ height: CGFloat) -> CGFloat { height >= 32 ? 8 : 7 }

    /// The segmented track pads its thumb by this much, so by the outer = inner + padding
    /// rule the thumb's corner is the track's less this.
    static let trackInset: CGFloat = 2
}

// MARK: - Buttons

/// The one button style for the window's bars.
///
/// Three weights, and only one of them is coloured: `primary` is the accent and is meant
/// to appear once per region — Download, Search. `secondary` is a plate one step lighter
/// than the bar it sits on, with a hairline, which is how it reads as raised without a
/// shadow. `ghost` is no plate at all until the pointer is over it, for chrome that should
/// stay out of the way (closing a panel).
///
/// A theme keeps its character through the edge, not the shape: a primary control wears
/// the theme's `themeEdge`, and a secondary one takes its hairline in the theme's tint,
/// the way `ThemedButtonStyle` does. Brackets round every control in a row were tried in
/// effect already (the old toolbar) and read as noise, so the edge is kept for the one
/// thing worth pointing at.
struct ChromeButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }

    var kind: Kind = .secondary
    var height: CGFloat = Chrome.control
    /// Icon-only: as wide as it is tall.
    var square = false
    /// A secondary control that is on — a bookmark that is set. Lit in the accent's tint
    /// rather than filled with it, so it never competes with the primary.
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        Plate(configuration: configuration, kind: kind, height: height, square: square, isOn: isOn)
    }

    private struct Plate: View {
        let configuration: Configuration
        let kind: Kind
        let height: CGFloat
        let square: Bool
        let isOn: Bool

        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            let shape = ThemedRect(cornerRadius: Chrome.radius(height), style: .continuous)
            let lit = hovering && enabled
            configuration.label
                .font(.system(size: height >= 32 ? 13 : 12,
                              weight: kind == .primary ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(ink(lit: lit))
                .padding(.horizontal, square ? 0 : 12)
                .frame(width: square ? height : nil, height: height)
                .frame(minWidth: square ? nil : height)
                .background(fill(lit: lit, pressed: configuration.isPressed), in: shape)
                .overlay { shape.strokeBorder(hairline(lit: lit), lineWidth: 1) }
                .modifier(PrimaryEdge(on: kind == .primary && enabled, shape: shape, lit: lit))
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.12), value: enabled)
                .pointingHand()
        }

        private var themed: Bool { Theme.active.id != .classic }

        private func ink(lit: Bool) -> Color {
            guard enabled else { return Palette.ink(0.32) }
            switch kind {
            case .primary: return Palette.onFill
            case .secondary: return isOn ? Palette.accent : Palette.ink(lit ? 1 : 0.85)
            case .ghost: return Palette.ink(lit ? 0.95 : 0.6)
            }
        }

        /// A disabled primary is drawn as a neutral plate, not as a faded accent: a pink
        /// button reads as a different, softer action rather than as one not ready yet.
        private func fill(lit: Bool, pressed: Bool) -> Color {
            switch kind {
            case .primary:
                guard enabled else { return Palette.ink(0.07) }
                return pressed ? Palette.accent.opacity(0.85) : (lit ? Palette.accentHot : Palette.accent)
            case .secondary:
                if isOn { return Palette.accent.opacity(lit ? 0.2 : 0.14) }
                return Palette.ink(pressed ? 0.16 : lit ? 0.11 : 0.065)
            case .ghost:
                return Palette.ink(pressed ? 0.14 : lit ? 0.08 : 0)
            }
        }

        private func hairline(lit: Bool) -> Color {
            switch kind {
            case .primary:
                return enabled ? .clear : Palette.ink(0.08)
            case .secondary:
                if isOn { return Palette.accent.opacity(0.4) }
                if themed { return Theme.active.edgeTint.opacity(lit ? 0.7 : 0.32) }
                return Palette.ink(lit ? 0.16 : 0.10)
            case .ghost:
                return .clear
            }
        }
    }

    /// The theme's edge, on the primary control only.
    private struct PrimaryEdge<S: InsettableShape>: ViewModifier {
        let on: Bool
        let shape: S
        let lit: Bool

        func body(content: Content) -> some View {
            if on { content.themeEdge(shape, lit: lit) } else { content }
        }
    }
}

extension ButtonStyle where Self == ChromeButtonStyle {
    static func chrome(_ kind: ChromeButtonStyle.Kind = .secondary,
                       height: CGFloat = Chrome.control,
                       square: Bool = false,
                       isOn: Bool = false) -> ChromeButtonStyle {
        ChromeButtonStyle(kind: kind, height: height, square: square, isOn: isOn)
    }
}

// MARK: - Segmented control

/// A row of mutually exclusive choices on one track, with the chosen one raised.
///
/// The channel's tabs were four separate accent capsules: every one of them looked like a
/// button you had not pressed yet, and the chosen one was as loud as Download. A segmented
/// control says "pick one of these" by its shape alone, and keeps the accent free for the
/// action that matters.
///
/// The thumb slides between segments, briefly, and simply appears under Reduce Motion.
struct ChromeSegmented<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let label: (Option) -> String
    let help: (Option) -> String
    let pick: (Option) -> Void

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let track = ThemedRect(cornerRadius: Chrome.radius(Chrome.control), style: .continuous)
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Segment(title: label(option), isOn: option == selection,
                        thumb: thumb, action: { pick(option) })
                    .help(help(option))
            }
        }
        .padding(Chrome.trackInset)
        .frame(height: Chrome.control)
        .background(Palette.ink(0.05), in: track)
        .overlay { track.strokeBorder(Palette.ink(0.09), lineWidth: 1) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selection)
    }

    private struct Segment: View {
        let title: String
        let isOn: Bool
        let thumb: Namespace.ID
        let action: () -> Void

        @State private var hovering = false
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let shape = ThemedRect(
                cornerRadius: Chrome.radius(Chrome.control) - Chrome.trackInset,
                style: .continuous)
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(Palette.ink(isOn ? 1 : hovering ? 0.85 : 0.58))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                    .background {
                        if isOn {
                            thumbFill(shape)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .pointingHand()
        }

        /// Raised by lightness: a lighter plate in the dark, the control background (white)
        /// with a contact shadow in the light — what a native segmented control does. A
        /// theme lights it in its own tint instead, so the chosen tab carries the theme.
        @ViewBuilder
        private func thumbFill(_ shape: ThemedRect) -> some View {
            if Theme.active.id != .classic {
                shape.fill(Theme.active.edgeTint.opacity(0.16))
                    .overlay { shape.strokeBorder(Theme.active.edgeTint.opacity(0.6), lineWidth: 1) }
            } else if scheme == .dark {
                shape.fill(Palette.ink(0.14))
                    .overlay { shape.strokeBorder(Palette.ink(0.08), lineWidth: 1) }
            } else {
                shape.fill(Palette.rowPlate)
                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 0.5)
            }
        }
    }
}

// MARK: - Field

/// A text field in a bar, at a control's height: the filter over a list.
struct ChromeField: View {
    let icon: String
    let prompt: String
    @Binding var text: String

    @FocusState private var focused: Bool

    var body: some View {
        let shape = ThemedRect(cornerRadius: Chrome.radius(Chrome.control), style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.ink(0.45))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink(0.4))
                }
                .buttonStyle(.plain)
                .help("Clear the filter")
                .accessibilityLabel("Clear the filter")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: Chrome.control)
        // Recessed rather than raised: a field is somewhere to put something, and reads
        // that way by sitting a shade darker than the plates beside it.
        .background(Palette.ink(0.035), in: shape)
        .overlay {
            shape.strokeBorder(focused ? Palette.accent.opacity(0.7) : Palette.ink(0.12),
                               lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

// MARK: - Bars

extension View {
    /// A toolbar row's surface: the system's bar material in Classic, as the footer already
    /// is, so the chrome above and below the list is one material; the theme's ground
    /// otherwise. A hairline closes it off from the page underneath.
    func chromeBar() -> some View {
        background {
            if Theme.active.id == .classic { Rectangle().fill(.bar) } else { Palette.ground }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.ink(0.10)).frame(height: 1)
        }
    }
}

/// A short vertical rule between groups of controls in a bar — the seam between the
/// channel's tabs and what acts on the list, say. Drawn, not a gap, because a gap wide
/// enough to read as a grouping wastes the width a narrow window needs.
struct ChromeSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.ink(0.12))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }
}
