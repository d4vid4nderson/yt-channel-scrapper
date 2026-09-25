import SwiftUI

/// Choosing a child's PIN on the Mac, on the same pad the phone will ask for it on.
///
/// A copy of the iPhone's `PINPad` layout — four dots, then 1–9, a gap, 0 and delete —
/// so the parent types it here in the shape they will next see it, on the child's phone,
/// when they need to get back in. Two text fields said "four digits" and "again" and
/// left the rest to the reader; this walks through it: the fourth digit moves straight
/// on to the confirmation, and a mismatch shakes and starts again.
///
/// The Mac keyboard works too — digits, delete — once the pad has focus, which it takes
/// as soon as it appears.
struct PINEntry: View {
    /// Set to the PIN once it has been entered twice and matched; nil until then, and
    /// again if the parent starts over.
    @Binding var pin: String?

    static let length = 4

    private enum Step { case enter, confirm, done }

    @State private var step: Step = .enter
    @State private var first = ""
    @State private var digits = ""
    @State private var wrong = false
    @State private var shake: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: step == .done ? "lock.fill" : "lock.rotation")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(step == .done ? Palette.good : Palette.accent)
                .padding(.bottom, 8)

            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Palette.ink(1))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(wrong ? Palette.accent : Palette.ink(0.45))
                .multilineTextAlignment(.center)
                .frame(height: 30, alignment: .top)
                .padding(.top, 3)

            dots
                .padding(.vertical, 12)
                .modifier(Shake(travel: shake))

            if step == .done {
                Button("Change PIN") { startOver() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .pointingHand()
                    .frame(height: 4 * 52 + 3 * 10, alignment: .top)
            } else {
                keypad
            }
        }
        .frame(width: 210)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(characters: .decimalDigits) { press in
            press.characters.forEach { type(String($0)) }
            return .handled
        }
        .onKeyPress(.delete) { delete(); return .handled }
        .animation(.easeOut(duration: 0.18), value: step)
        .animation(.easeOut(duration: 0.18), value: wrong)
    }

    // MARK: - Pieces

    private var title: String {
        switch step {
        case .enter:   "Choose a PIN"
        case .confirm: "Enter it again"
        case .done:    "PIN set"
        }
    }

    private var detail: String {
        if wrong { return "Those did not match. Choose a PIN again." }
        switch step {
        case .enter:   return "The only way out of Minor Mode. Not a birthday."
        case .confirm: return "To make sure."
        case .done:    return "You will type this on the phone to unlock it."
        }
    }

    private var dots: some View {
        HStack(spacing: 14) {
            ForEach(0..<Self.length, id: \.self) { index in
                let filled = step == .done || index < digits.count
                Circle()
                    .strokeBorder(wrong ? Palette.accent : Palette.ink(0.35), lineWidth: 1.3)
                    .background(Circle().fill(filled ? (wrong ? Palette.accent : Palette.ink(0.92)) : .clear))
                    .frame(width: 11, height: 11)
            }
        }
    }

    private static let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"],
    ]

    private var keypad: some View {
        VStack(spacing: 10) {
            ForEach(Self.rows, id: \.first) { row in
                HStack(spacing: 14) {
                    ForEach(row, id: \.self) { key($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func key(_ key: String) -> some View {
        switch key {
        case "":
            Color.clear.frame(width: 52, height: 52)
        case "⌫":
            Button(action: delete) {
                Image(systemName: "delete.left")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.ink(0.6))
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(digits.isEmpty ? 0.3 : 1)
            .help("Delete")
        default:
            Button { type(key) } label: {
                Text(key)
                    .font(.system(size: 21, weight: .regular, design: .rounded))
                    .foregroundStyle(Palette.ink(0.95))
                    .frame(width: 52, height: 52)
                    .background(Palette.ink(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(Palette.ink(0.10)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressedKey())
            .pointingHand()
        }
    }

    // MARK: - Typing

    private func type(_ digit: String) {
        guard step != .done, digits.count < Self.length else { return }
        wrong = false
        digits += digit
        guard digits.count == Self.length else { return }

        // A beat on the full row of dots before moving on, so the fourth press is seen
        // to land rather than the pad jumping the moment it is touched.
        let entered = digits
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard digits == entered else { return }
            switch step {
            case .enter:
                first = entered
                digits = ""
                step = .confirm
            case .confirm where entered == first:
                digits = ""
                step = .done
                pin = entered
            case .confirm:
                first = ""
                digits = ""
                step = .enter
                wrong = true
                withAnimation(.linear(duration: 0.35)) { shake += 1 }
            case .done:
                break
            }
        }
    }

    private func delete() {
        guard step != .done, !digits.isEmpty else { return }
        digits.removeLast()
        wrong = false
    }

    private func startOver() {
        pin = nil
        first = ""
        digits = ""
        wrong = false
        step = .enter
        focused = true
    }
}

/// A key that dims while held, like the phone's.
private struct PressedKey: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

/// Side to side, for a PIN that did not match.
private struct Shake: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(travel * .pi * 4), y: 0))
    }
}
