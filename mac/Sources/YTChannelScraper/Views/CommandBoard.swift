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

    private var dispatch: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Dispatch")

            if shelf.roster.isEmpty {
                Button { model.showFamily = true } label: {
                    Text("Add a minor, then drag a channel or video onto them")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .pointingHand()
            } else {
                ForEach(shelf.roster, id: \.id) { minor in
                    MinorLine(
                        name: minor.name,
                        approved: shelf.approved(for: minor.id).count,
                        device: shelf.devices.first { $0.personID == minor.id },
                        expected: shelf.expectedDevice(for: minor.id),
                        sent: justSent?.minor == minor.id ? justSent?.title : nil,
                        isOver: over == minor.id
                    )
                    .dropDestination(for: String.self) { items, _ in
                        // A person's id would arrive here as a bare UUID; only an item
                        // decodes, so anything else is declined rather than acted on.
                        guard let raw = items.first,
                              let item = SendPayload(encoded: raw) else { return false }
                        send(item, to: minor)
                        return true
                    } isTargeted: { targeted in
                        over = targeted ? minor.id : nil
                    }
                }
            }
        }
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

/// One minor: what they have been sent, and how much of it is actually on their device.
private struct MinorLine: View {
    let name: String
    let approved: Int
    let device: DeviceRecord?
    let expected: DeviceRecord.Kind?
    /// What was just dropped here, if anything.
    let sent: String?
    let isOver: Bool

    var body: some View {
        HStack(spacing: 11) {
            ProgressArc(done: device?.downloaded ?? 0, total: approved)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                if let sent {
                    Label("Sent " + sent, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent.opacity(0.9))
                        .lineLimit(1)
                } else {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }

            Spacer(minLength: 8)

            if let device {
                Image(systemName: device.kind.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .help("\(device.name) — last seen "
                          + device.lastSeen.formatted(date: .abbreviated, time: .shortened))
            } else if let expected {
                Image(systemName: expected.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.16))
                    .help("Expected, but this device has not opened the app yet")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isOver ? Palette.accent.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isOver ? Palette.accent.opacity(0.4) : .clear)
        }
        .animation(.easeOut(duration: 0.12), value: isOver)
        .animation(.easeOut(duration: 0.18), value: sent)
        .help("Drag a channel or video from the Saved panel onto \(name) to send it")
    }

    /// Says the gap where there is one, because the gap is the thing worth knowing.
    private var status: String {
        guard approved > 0 else { return "nothing sent yet" }
        guard let device else { return "\(approved) sent · no device yet" }
        let waiting = max(0, approved - device.downloaded)
        if waiting == 0 { return "\(approved) sent · all downloaded" }
        return "\(approved) sent · \(waiting) still coming"
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
