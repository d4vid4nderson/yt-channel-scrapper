import SwiftUI

/// The idle screen's reason to exist: what is going on, before you have typed anything.
///
/// It replaced a lone row of chips under the search, which made the landing read as a
/// search box with an afterthought. A command centre should answer the question you
/// opened it with — *has what I sent actually landed?* — without you asking.
///
/// ## The one number
///
/// Every row leads with an arc of downloaded-over-approved. A count would say "3 videos";
/// the arc says "3 sent, 1 still coming", which is the difference between a statistic and
/// an answer. It is also the only fact here that no other screen can tell you: it comes
/// from the child's own device reporting in.
///
/// ## Depth
///
/// One raised surface, hairline-bordered, with internal rules — the same strategy as the
/// drawers rather than a second one. Shadows are avoided deliberately: this sits over the
/// aurora, and a drop shadow on a glow reads as smear.
struct CommandBoard: View {
    @Bindable var model: AppModel

    private var shelf: ShelfStore { model.shelf }

    /// Who most recently received something, and what — shown on their own row for a
    /// moment. A modal would be the wrong confirmation for a drag: the gesture is already
    /// deliberate, and what you want back is "it landed", not another button to press.
    @State private var justSent: (minor: UUID, title: String)?
    @State private var over: UUID?

    var body: some View {
        Group {
            if model.profiles.guardian == nil || shelf.folder == nil {
                setup
            } else {
                board
            }
        }
        .frame(maxWidth: 680)
        .padding(.top, 34)
    }

    // MARK: - Before there is a family

    /// Deliberately not a card. With nothing to report, a bordered panel containing one
    /// sentence is a frame around an apology.
    private var setup: some View {
        Button {
            model.showFamily = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2.badge.plus").font(.system(size: 12))
                Text("Set up your family to start sending videos")
                    .font(.system(size: 12.5))
            }
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.white.opacity(0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .pointingHand()
    }

    // MARK: - The board

    private var board: some View {
        HStack(alignment: .top, spacing: 0) {
            dispatch
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(width: 1)
                // Spans whatever the columns turn out to be, rather than demanding
                // height of its own — a bare 1pt Rectangle is greedy vertically and was
                // stretching the whole panel to the bottom of the window.
                .frame(maxHeight: .infinity)

            // Narrower on purpose: this column is reference, the other is the answer.
            // Equal halves would say they matter equally.
            meta
                .frame(width: 186, alignment: .leading)
                .padding(16)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08))
        }
    }

    /// Everybody in the family, and what each of their devices is holding.
    ///
    /// Anyone can be sent to, admins included — a shelf is just a list of things addressed
    /// to somebody. What differs is what the receiving device does with it. A minor's
    /// device reconciles: it fetches what is approved *and deletes what is not*, which is
    /// what makes a veto real. An admin's device only fetches. Sweeping a parent's machine
    /// against a list somebody else writes would delete their own library, so it never
    /// happens.
    private var dispatch: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Dispatch")

            if shelf.guardians.isEmpty && shelf.roster.isEmpty {
                Button { model.showFamily = true } label: {
                    Text("Add someone, then drag a channel or video onto their device")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .pointingHand()
            } else {
                ForEach(shelf.guardians, id: \.id) { person in
                    PersonBlock(
                        name: person.name,
                        isMinor: false,
                        approved: shelf.approved(for: person.id).count,
                        devices: devices(of: person.id),
                        expected: shelf.expectedDevice(for: person.id),
                        sentTitle: justSent?.minor == person.id ? justSent?.title : nil,
                        isOver: over == person.id,
                        onDrop: { payload, targeted in
                            if let payload {
                                send(payload, to: Profiles.Minor(id: person.id, name: person.name))
                            }
                            over = targeted ? person.id : over
                        }
                    )
                }
                ForEach(shelf.roster, id: \.id) { person in
                    PersonBlock(
                        name: person.name,
                        isMinor: true,
                        approved: shelf.approved(for: person.id).count,
                        devices: devices(of: person.id),
                        expected: shelf.expectedDevice(for: person.id),
                        sentTitle: justSent?.minor == person.id ? justSent?.title : nil,
                        isOver: over == person.id,
                        onDrop: { payload, targeted in
                            if let payload { send(payload, to: person) }
                            over = targeted ? person.id : over
                        }
                    )
                }
            }
        }
    }

    private func devices(of person: UUID) -> [DeviceRecord] {
        shelf.devices.filter { $0.personID == person }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Library")
            stat("\(model.library.channels.count)", "channels")
            stat("\(model.library.videos.count)", "videos kept")

            Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.vertical, 2)

            title("Downloads")
            stat("\(model.downloader.activeCount)",
                 model.downloader.activeCount == 1 ? "running" : "running",
                 lit: model.downloader.activeCount > 0)
        }
    }

    private func send(_ item: SendPayload, to minor: Profiles.Minor) {
        Task {
            guard await model.send(item, to: minor) else { return }
            justSent = (minor.id, item.title)
            // Long enough to read, short enough not to become part of the layout.
            try? await Task.sleep(for: .seconds(2.6))
            if justSent?.minor == minor.id { justSent = nil }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.35))
            .textCase(.uppercase)
            .tracking(0.7)
    }

    /// Value first and heaviest, label demoted — three tiers out of one type size, which
    /// is what keeps a figure from reading as body text.
    private func stat(_ value: String, _ label: String, lit: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 19, weight: .semibold).monospacedDigit())
                .foregroundStyle(lit ? Palette.accent : .white.opacity(0.92))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

/// One person, with their devices under their name.
///
/// The device is the drop target, not the name — which is how somebody thinks about it
/// ("put this on Wyatt's phone") even though the shelf underneath is per person. Dropping
/// on any of somebody's devices sends to that person; their devices then all pick it up.
///
/// A minor with no device still gets a target, because you have to be able to send things
/// before their phone has ever been set up.
private struct PersonBlock: View {
    let name: String
    let isMinor: Bool
    let approved: Int?
    let devices: [DeviceRecord]
    let expected: DeviceRecord.Kind?
    let sentTitle: String?
    let isOver: Bool
    /// Nil for an admin — see `dispatch`. Called with the payload on a drop, and with nil
    /// when only the hover state changed.
    let onDrop: ((SendPayload?, Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let approved {
                    ProgressArc(done: devices.map(\.downloaded).max() ?? 0, total: approved)
                } else {
                    Circle()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 2.5)
                        .frame(width: 30, height: 30)
                }

                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(isMinor ? 1 : 0.7))

                if !isMinor {
                    Text("admin")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(.white.opacity(0.06), in: Capsule())
                }

                Spacer(minLength: 6)

                if let sentTitle {
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.accent.opacity(0.9))
                        .help("Sent " + sentTitle)
                }
            }

            deviceRows
                .padding(.leading, 38)
        }
    }

    @ViewBuilder
    private var deviceRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            if devices.isEmpty {
                slot(icon: expected?.icon ?? "questionmark.circle",
                     text: expected == nil ? "no device yet" : "not seen yet",
                     detail: nil)
            } else {
                ForEach(devices) { device in
                    slot(icon: device.kind.icon,
                         text: device.kind.noun.capitalized,
                         detail: isMinor && approved != nil
                            ? "\(device.downloaded) of \(approved ?? 0)"
                            : device.lastSeen.formatted(date: .omitted, time: .shortened))
                }
            }
        }
    }

    private func slot(icon: String, text: String, detail: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10.5))
            Text(text).font(.system(size: 11))
            if let detail {
                Text("· " + detail)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer(minLength: 4)
        }
        .foregroundStyle(.white.opacity(devices.isEmpty ? 0.28 : 0.45))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isOver ? Palette.accent.opacity(0.14) : .white.opacity(0.03),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isOver ? Palette.accent.opacity(0.45) : .white.opacity(0.05))
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .modifier(DropTarget(onDrop: onDrop))
        .help("Drop a channel or video here to send it to " + name)
        .animation(.easeOut(duration: 0.12), value: isOver)
    }
}

/// Applied to every device slot, but only live for those that can receive. An admin's
/// slot has no drop destination at all rather than one that refuses — a target that
/// highlights and then declines is worse than one that never lit up.
private struct DropTarget: ViewModifier {
    let onDrop: ((SendPayload?, Bool) -> Void)?

    func body(content: Content) -> some View {
        if let onDrop {
            content.dropDestination(for: String.self) { items, _ in
                guard let raw = items.first,
                      let payload = SendPayload(encoded: raw) else { return false }
                onDrop(payload, false)
                return true
            } isTargeted: { targeted in
                onDrop(nil, targeted)
            }
        } else {
            content
        }
    }
}

/// The signature. An arc rather than a number, because the interesting thing is the gap
/// between what was sent and what arrived — which a count cannot show and a ring can.
private struct ProgressArc: View {
    let done: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Palette.accent.opacity(total == 0 ? 0 : 0.9),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                // From the top, clockwise. The default start is three o'clock, which
                // reads as a gauge rather than as progress.
                .rotationEffect(.degrees(-90))
            Text(total == 0 ? "–" : "\(done)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(total == 0 ? 0.3 : 0.85))
        }
        .frame(width: 30, height: 30)
        .animation(.easeOut(duration: 0.25), value: fraction)
    }
}
