import SwiftUI
import UIKit

/// The four digits, and the keypad that enters them.
///
/// One view for the three things that need a PIN — setting the first one, changing it,
/// and getting back out of Minor Mode — because they are the same screen with different
/// words on it, and because the fiddly parts (the dots filling, the shake, the penalty
/// countdown) are worth writing once.
///
/// Its own number pad rather than a `TextField` with `.keyboardType(.numberPad)`: the
/// system keyboard on a locked screen brings a dictation key, a paste menu and — on a
/// minor's phone — whatever keyboard extension is installed. A grid of ten buttons has
/// none of that, and can be sized for a thumb.
struct PINPad: View {
    enum Purpose {
        /// Minor back to parent. Offers biometrics, and counts wrong answers.
        case unlock
        /// No PIN yet: enter one, then repeat it.
        case create
        /// Enter the old one, then the new one twice.
        case change
    }

    @Bindable var profiles: Profiles
    let purpose: Purpose
    /// Called once the whole flow has succeeded. `unlock` has already switched the mode
    /// by then; `create` and `change` have already stored the new PIN.
    let onDone: () -> Void
    /// Nil when there is no way to back out — the lock screen the minor sees.
    var onCancel: (() -> Void)?

    /// Which of the up-to-three entries is being typed.
    private enum Step { case verify, enter, confirm }

    @State private var step: Step
    @State private var digits = ""
    @State private var first = ""
    @State private var wrong = false
    /// What was wrong, set at the point of rejection. A mismatched confirmation moves
    /// `step` back to `.enter` as it fails, so the step alone can no longer say.
    @State private var problem = ""
    @State private var shake: CGFloat = 0
    /// Re-read every second while a penalty is running, so the countdown moves.
    @State private var now = Date()

    private static let length = 4

    init(profiles: Profiles,
         purpose: Purpose,
         onDone: @escaping () -> Void,
         onCancel: (() -> Void)? = nil) {
        self.profiles = profiles
        self.purpose = purpose
        self.onDone = onDone
        self.onCancel = onCancel
        _step = State(initialValue: purpose == .create ? .enter : .verify)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.accent)
                .padding(.bottom, 18)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primaryText)

            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(wrong ? Palette.accent : Color.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .frame(height: 34, alignment: .top)
                .padding(.top, 6)

            dots
                .padding(.vertical, 22)
                .modifier(Shake(travel: shake))

            keypad
                .disabled(isFrozen)
                .opacity(isFrozen ? 0.4 : 1)

            Spacer(minLength: 0)

            footer
                .frame(height: 44)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ground()
        .animation(.easeOut(duration: 0.2), value: step)
        .animation(.easeOut(duration: 0.2), value: wrong)
        // Only runs while there is a countdown to run down.
        .task(id: profiles.lockedUntil) {
            while profiles.penalty != nil {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
            now = Date()
        }
        // The fast path for a parent on their own device, offered as the screen appears
        // rather than behind a button press.
        .task {
            guard purpose == .unlock, profiles.useFaceID, profiles.penalty == nil else { return }
            if await profiles.unlockWithBiometrics() { onDone() }
        }
    }

    // MARK: - Pieces

    private var dots: some View {
        HStack(spacing: 20) {
            ForEach(0..<Self.length, id: \.self) { index in
                Circle()
                    .strokeBorder(wrong ? Palette.accent : Color.white.opacity(0.35), lineWidth: 1.5)
                    .background(Circle().fill(fill(at: index)))
                    .frame(width: 15, height: 15)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(digits.count) of \(Self.length) digits entered")
    }

    private func fill(at index: Int) -> Color {
        guard index < digits.count else { return .clear }
        return wrong ? Palette.accent : Color.primaryText
    }

    private var keypad: some View {
        VStack(spacing: 16) {
            ForEach(Self.rows, id: \.first) { row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    /// The last row is off-centre by one: an empty slot, zero, delete. Laid out as a
    /// row of three so the zero lands under the eight rather than under the seven.
    private static let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"],
    ]

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        switch key {
        case "":
            Color.clear.frame(width: 72, height: 72)
        case "⌫":
            Button {
                guard !digits.isEmpty else { return }
                digits.removeLast()
                wrong = false
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.secondaryText)
                    .frame(width: 72, height: 72)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(digits.isEmpty ? 0.3 : 1)
            .accessibilityLabel("Delete")
        default:
            Button { type(key) } label: {
                Text(key)
                    .font(.system(size: 28, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                    .frame(width: 72, height: 72)
                    .background(Color.card, in: Circle())
                    .overlay(Circle().stroke(Color.hairline))
            }
            .buttonStyle(PressedKey())
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if let onCancel {
                Button("Cancel") { onCancel() }
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            if purpose == .unlock, profiles.useFaceID, let name = profiles.biometryName,
               penalty == nil {
                Button {
                    Task { if await profiles.unlockWithBiometrics() { onDone() } }
                } label: {
                    Label(name, systemImage: name == "Touch ID" ? "touchid" : "faceid")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Palette.accent)
            }
        }
        .font(.system(size: 15))
    }

    // MARK: - Words

    private var icon: String {
        switch (purpose, step) {
        case (.unlock, _):  return "lock"
        case (.change, .verify): return "lock"
        default: return "lock.rotation"
        }
    }

    private var title: String {
        switch (purpose, step) {
        case (.unlock, _):       return "Minor Mode is on"
        case (.change, .verify): return "Enter your current PIN"
        case (_, .confirm):      return "Enter it again"
        default:                 return "Choose a PIN"
        }
    }

    private var detail: String {
        if let seconds = penalty {
            return "Too many wrong tries. Try again in \(Self.wait(seconds))."
        }
        if wrong { return problem }
        switch (purpose, step) {
        case (.unlock, _):
            return "Enter the parent PIN to turn it off and get the Search tab back."
        case (.change, .verify):
            return ""
        case (_, .confirm):
            return ""
        default:
            return "Four digits. You will need this to turn Minor Mode off, so pick "
                + "something they will not guess — not a birthday."
        }
    }

    private static func wait(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        if whole < 60 { return "\(whole)s" }
        let minutes = Int((seconds / 60).rounded(.up))
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    /// Seconds left on the guessing penalty. Recomputed against `now` rather than read
    /// from `profiles`, because it is `now` advancing that redraws this screen — the
    /// model's own copy reads the clock directly and so changes nothing observable.
    private var penalty: TimeInterval? {
        guard let until = profiles.lockedUntil else { return nil }
        let remaining = until.timeIntervalSince(now)
        return remaining > 0 ? remaining : nil
    }

    private var isFrozen: Bool { penalty != nil }

    // MARK: - Entry

    private func type(_ key: String) {
        guard digits.count < Self.length, !isFrozen else { return }
        wrong = false
        digits.append(key)
        guard digits.count == Self.length else { return }
        // A beat with all four dots filled before the screen changes under them —
        // otherwise the fourth tap appears to do nothing and then everything at once.
        let entered = digits
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            submit(entered)
        }
    }

    private func submit(_ entered: String) {
        switch step {
        case .verify:
            if purpose == .unlock {
                if profiles.unlock(with: entered) {
                    succeed()
                } else {
                    reject("Wrong PIN.")
                }
            } else if profiles.matches(entered) {
                digits = ""
                step = .enter
            } else {
                reject("Wrong PIN.")
            }

        case .enter:
            first = entered
            digits = ""
            step = .confirm

        case .confirm:
            if entered == first {
                // The Keychain can refuse, and if it does there is no PIN — so this
                // says so rather than returning to a settings screen that would claim
                // Minor Mode is ready to use.
                if profiles.setPIN(entered) {
                    succeed()
                } else {
                    first = ""
                    step = .enter
                    reject("This phone would not store the PIN. Try again.")
                }
            } else {
                // Both entries go, not just the second: "they did not match" gives no
                // hint about which one was the slip, so retyping both is the only
                // honest thing to ask for.
                first = ""
                step = .enter
                reject("Those did not match. Start again.")
            }
        }
    }

    private func succeed() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        digits = ""
        onDone()
    }

    private func reject(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        problem = message
        wrong = true
        withAnimation(.linear(duration: 0.4)) { shake += 1 }
        // Left on screen for the length of the shake, so the dots being wrong is
        // something you see rather than something you infer.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            digits = ""
        }
    }
}

/// Side-to-side, three times, on a wrong entry. The one animation in the app that says
/// "no" without words.
private struct Shake: GeometryEffect {
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: 9 * sin(travel * .pi * 6), y: 0))
    }
}

/// Keys dim as they go down. `.plain` alone gives no feedback at all, and `.bordered`
/// brings a shape that fights the circle.
private struct PressedKey: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.45 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
