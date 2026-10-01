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

    var body: some View {
        Group {
            if model.profiles.guardian == nil || shelf.folder == nil {
                setup
            } else {
                board
            }
        }
        .frame(maxWidth: 680)
        .padding(.top, 18)
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
            .foregroundStyle(Palette.ink(0.65))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Palette.ink(0.07), in: ThemedCapsule())
            .overlay(ThemedCapsule().strokeBorder(Palette.ink(0.10)))
        }
        .buttonStyle(.plain)
        .pointingHand()
    }

    // MARK: - The board

    /// A breath of ink over the aurora — and over a picture (Blade Runner's street, Dune's
    /// storm, the Shire), frosted
    /// glass with the surface through it, since a sign behind the text made it unreadable.
    @ViewBuilder
    private var boardFill: some View {
        let shape = ThemedRect(cornerRadius: 14)
        if [.city, .dunes, .parchment].contains(Theme.active.backdrop) {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Palette.surface.opacity(0.62))
            }
        } else {
            shape.fill(Palette.ink(0.035))
        }
    }

    private var board: some View {
        HStack(alignment: .top, spacing: 0) {
            dispatch
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 16)

            Rectangle()
                .fill(Palette.ink(0.07))
                .frame(width: 1)
                // Spans whatever the columns turn out to be, rather than demanding
                // height of its own — a bare 1pt Rectangle is greedy vertically and was
                // stretching the whole panel to the bottom of the window.
                .frame(maxHeight: .infinity)

            // Narrower on purpose: this column is reference, the other is the answer.
            // Equal halves would say they matter equally.
            meta
                .frame(width: 186, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background { boardFill }
        .overlay {
            ThemedRect(cornerRadius: 14).strokeBorder(Palette.ink(0.08))
        }
        .themeEdge(radius: 14)
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
            HStack {
                title("Dispatch")
                Spacer()
                Button {
                    model.focusedDevice = nil
                    model.showDevices = true
                } label: {
                    Label("Devices", systemImage: "list.bullet.rectangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink(0.5))
                }
                .buttonStyle(.plain)
                .help("What every device holds, the computer included")
                .pointingHand()
                .padding(.trailing, 10)
                Button {
                    model.showPhoneSetup = true
                } label: {
                    Label("Set up a child's phone", systemImage: "iphone.badge.plus")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink(0.5))
                }
                .buttonStyle(.plain)
                .help("Install the app on a plugged-in phone and lock it to one child")
                .pointingHand()
            }

            if shelf.guardians.isEmpty && shelf.roster.isEmpty {
                Button { model.showFamily = true } label: {
                    Text("Add someone, then drag a channel or video onto their device")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink(0.45))
                }
                .buttonStyle(.plain)
                .pointingHand()
            } else {
                ForEach(shelf.guardians, id: \.id) { person in
                    PersonBlock(
                        name: person.name,
                        isMinor: false,
                        approved: shelf.approved(for: person.id).count,
                        devices: shelf.devices(of: person.id),
                        expected: shelf.expectedDevice(for: person.id),
                        sentTitle: justSent?.minor == person.id ? justSent?.title : nil,
                        onOpen: open,
                        onDrop: { payload in
                            if let payload {
                                send(payload, to: Profiles.Minor(id: person.id, name: person.name))
                            }
                        }
                    )
                }
                ForEach(shelf.roster, id: \.id) { person in
                    PersonBlock(
                        name: person.name,
                        isMinor: true,
                        approved: shelf.approved(for: person.id).count,
                        devices: shelf.devices(of: person.id),
                        expected: shelf.expectedDevice(for: person.id),
                        sentTitle: justSent?.minor == person.id ? justSent?.title : nil,
                        onOpen: open,
                        onDrop: { payload in
                            if let payload { send(payload, to: person) }
                        }
                    )
                }
            }

            // Only when there is something to tidy. Every reinstall of the phone app used
            // to leave its old record behind as a second, identical phone.
            if !shelf.clutter.isEmpty {
                Button {
                    model.focusedDevice = shelf.clutter.first?.id
                    model.showDevices = true
                } label: {
                    Label(clutterText, systemImage: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent.opacity(0.9))
                }
                .buttonStyle(.plain)
                .pointingHand()
            }

            NearbySection(model: model)
        }
    }

    private var clutterText: String {
        let n = shelf.clutter.count
        return "\(n) duplicate or old device\(n == 1 ? "" : "s") — review and clean up"
    }

    private func open(_ device: UUID) {
        model.focusedDevice = device
        model.showDevices = true
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Library")
            stat("\(model.library.channels.count)", "channels")
            stat("\(model.library.videos.count)", "videos kept")

            Rectangle().fill(Palette.ink(0.07)).frame(height: 1).padding(.vertical, 2)

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
            // If their phone is in reach, have it fetch now rather than whenever it is
            // next opened.
            Task { await model.nearby.sync(childID: minor.id, shelf: model.shelf, guardian: model.profiles.guardian) }
            // Long enough to read, short enough not to become part of the layout.
            try? await Task.sleep(for: .seconds(2.6))
            if justSent?.minor == minor.id { justSent = nil }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .displayType(10, classic: .semibold)
            .foregroundStyle(Palette.ink(0.35))
            .textCase(.uppercase)
            .tracking(0.7)
    }

    /// Value first and heaviest, label demoted — three tiers out of one type size, which
    /// is what keeps a figure from reading as body text.
    private func stat(_ value: String, _ label: String, lit: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 19, weight: .semibold).monospacedDigit())
                .foregroundStyle(lit ? Palette.accent : Palette.ink(0.92))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink(0.4))
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
    let onOpen: (UUID) -> Void
    let onDrop: ((SendPayload?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let approved {
                    ProgressArc(done: devices.map(\.downloaded).max() ?? 0,
                                total: approved, isMinor: isMinor)
                } else {
                    Circle()
                        .strokeBorder(Palette.ink(0.12), lineWidth: 2.5)
                        .frame(width: 30, height: 30)
                }

                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink(isMinor ? 1 : 0.7))

                if !isMinor {
                    Text("admin")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Palette.ink(0.3))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Palette.ink(0.06), in: ThemedCapsule())
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
        VStack(alignment: .leading, spacing: 4) {
            // Dispatch is a list of destinations, and a computer is not one: no Mac
            // fetches what it is sent, so a row for one is only somewhere to mis-drop.
            // Computers still show in the Family panel, which is where you go to check
            // a device is reporting at all.
            let destinations = devices.filter { $0.kind != .computer }
            let awaited: DeviceRecord.Kind? = expected == .computer ? nil : expected

            ForEach(destinations) { device in
                DeviceSlot(
                    icon: device.kind.icon,
                    text: device.kind.noun.capitalized,
                    detail: isMinor && approved != nil
                        ? "\(device.downloaded) of \(approved ?? 0)"
                        : device.lastSeen.formatted(date: .omitted, time: .shortened),
                    dim: false,
                    name: name,
                    onOpen: { onOpen(device.id) },
                    onDrop: onDrop
                )
            }

            // A device chosen but not yet reporting is still a destination — you have to
            // be able to send to somebody's phone before that phone has opened the app.
            // With nothing chosen and nothing reporting, the empty slot is the invitation.
            if let awaited, !destinations.contains(where: { $0.kind == awaited }) {
                DeviceSlot(icon: awaited.icon, text: "not seen yet", detail: nil,
                           dim: true, name: name, onOpen: nil, onDrop: onDrop)
            } else if destinations.isEmpty {
                DeviceSlot(icon: "questionmark.circle", text: "no device yet", detail: nil,
                           dim: true, name: name, onOpen: nil, onDrop: onDrop)
            }
        }
    }
}

/// One device, holding its own drop state.
///
/// That state used to live on the person, so hovering one of somebody's devices lit every
/// device they had. A slot is what gets dropped on, so a slot is what knows.
private struct DeviceSlot: View {
    let icon: String
    let text: String
    let detail: String?
    let dim: Bool
    let name: String
    /// Opens this device in the Devices list. Nil for a placeholder slot, which has no
    /// device behind it to show.
    let onOpen: (() -> Void)?
    let onDrop: ((SendPayload?) -> Void)?

    @State private var over = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10.5))
            Text(text).font(.system(size: 11))
            if let detail {
                Text("· " + detail)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Palette.ink(0.3))
            }
            Spacer(minLength: 4)
        }
        .foregroundStyle(Palette.ink(dim ? 0.28 : 0.45))
        .padding(.horizontal, 10)
        .frame(minHeight: 34, alignment: .leading)
        .background(
            over ? Palette.accent.opacity(0.14) : Palette.ink(0.03),
            in: ThemedRect(cornerRadius: 7)
        )
        .overlay {
            ThemedRect(cornerRadius: 7)
                .strokeBorder(over ? Palette.accent.opacity(0.45) : Palette.ink(0.05))
        }
        .contentShape(ThemedRect(cornerRadius: 7))
        .onTapGesture { onOpen?() }
        .modifier(DropTarget(onDrop: onDrop, over: $over))
        .help(onOpen == nil
              ? "Drop a channel or video here to send it to " + name
              : "Click to see what is on it. Drop a channel or video here to send it to " + name)
        .animation(.easeOut(duration: 0.12), value: over)
    }
}

/// Applied to every device slot, but only live for those that can receive. An admin's
/// slot has no drop destination at all rather than one that refuses — a target that
/// highlights and then declines is worse than one that never lit up.
private struct DropTarget: ViewModifier {
    let onDrop: ((SendPayload?) -> Void)?
    @Binding var over: Bool

    func body(content: Content) -> some View {
        if let onDrop {
            content.dropDestination(for: String.self) { items, _ in
                guard let raw = items.first,
                      let payload = SendPayload(encoded: raw) else { return false }
                onDrop(payload)
                over = false
                return true
            } isTargeted: { targeted in
                over = targeted
            }
        } else {
            content
        }
    }
}

/// The signature: has what you sent this person actually landed?
///
/// Three states, and the colour is the point. Red while something is outstanding, a quiet
/// check once nothing is — which is the opposite of the usual green tick, deliberately.
/// On a board of five people the eye should go to the row that still owes you something;
/// "all fine" does not need saying in colour, and five red ticks for five finished rows
/// would say nothing at all.
///
/// What counts as landed differs by device, because they do different jobs with what they
/// are sent. A minor's phone downloads it, so the number is files on disk. An admin's
/// downloads nothing on its own — it offers an inbox — so it is how much of that inbox
/// has been dealt with. The tooltip says which; the question is the same either way.
///
/// The gap is real rather than cosmetic: `total` is counted here, from the files this Mac
/// just wrote, and `done` is whatever that device last reported about itself. So sending
/// something opens the ring immediately and it closes only when the far device has synced
/// and acted — which is exactly the interval worth showing.
private struct ProgressArc: View {
    let done: Int
    let total: Int
    var isMinor = false

    private var landed: Bool { total > 0 && done >= total }
    private var outstanding: Int { max(0, total - done) }

    private var explanation: String {
        guard total > 0 else { return "Nothing sent to them yet" }
        if landed {
            return isMinor
                ? "All \(total) approved videos are on their device"
                : "All \(total) sent items dealt with — their inbox is clear"
        }
        let left = "\(outstanding) of \(total) "
        return isMinor
            ? left + "still to download onto their device"
            : left + "still waiting in their inbox"
    }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.ink(0.10), lineWidth: 2.5)

            if landed {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink(0.5))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Palette.accent.opacity(total == 0 ? 0 : 0.9),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    // From the top, clockwise. The default start is three o'clock, which
                    // reads as a gauge rather than as progress.
                    .rotationEffect(.degrees(-90))

                // What is still owed, not what has arrived. The arc already says how far
                // along it is; the number is better spent on the part you can act on.
                Text(total == 0 ? "–" : "\(outstanding)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.ink(total == 0 ? 0.3 : 0.85))
            }
        }
        .frame(width: 30, height: 30)
        .help(explanation)
        .animation(.easeOut(duration: 0.25), value: fraction)
        .animation(.easeOut(duration: 0.2), value: landed)
    }
}

/// Phones in reach of this Mac right now — on the cable or the same Wi-Fi — each with a
/// way to make it sync on the spot.
///
/// Separate from the people above on purpose. Those are who things are *for*, and come
/// from the family folder; these are what this Mac can *touch*, and come from the cable
/// and the network. A phone appears under its child's name once this Mac has set it up.
private struct NearbySection: View {
    @Bindable var model: AppModel

    private var nearby: NearbyPhones { model.nearby }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nearby")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.ink(0.35))
                    .textCase(.uppercase)
                    .tracking(0.7)
                Spacer()
                Button {
                    Task { await nearby.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.ink(0.4))
                .help("Look for phones again")
                .pointingHand()
            }

            if !nearby.isAvailable {
                hint("Syncing over the cable or Wi-Fi needs Xcode on this Mac.")
            } else if nearby.phones.isEmpty {
                hint("No phones in reach. Plug one in, or turn on “Show this iPhone when on "
                     + "Wi-Fi” for it in Finder.")
            } else {
                ForEach(nearby.phones) { phone in row(phone) }
            }
        }
        .padding(.top, 6)
        .onAppear { nearby.startWatching() }
        .onDisappear { nearby.stopWatching() }
    }

    private func row(_ phone: PhoneDeployer.Phone) -> some View {
        let owner = nearby.owner(of: phone).flatMap { id in
            model.shelf.roster.first { $0.id == id }
        }
        return HStack(spacing: 8) {
            Image(systemName: phone.model.contains("iPad") ? "ipad" : "iphone")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink(0.6))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(phone.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.ink(0.9))
                Text([owner.map { "\($0.name)'s" }, phone.isWired ? "Cable" : "Wi-Fi", statusText(phone)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(isFailed(phone) ? Palette.warn : Palette.ink(0.42))
                    .lineLimit(2)
                    .help(statusText(phone) ?? "")
            }
            Spacer(minLength: 6)
            if case .syncing = nearby.status[phone.id] {
                ProgressView().controlSize(.mini)
            } else {
                // Offered on every phone, not only ones this Mac set up: all it does is
                // open the app, which is harmless anywhere it is installed.
                if owner == nil {
                    Button("Set up…") { model.showPhoneSetup = true }
                        .font(.system(size: 11))
                        .help("Make this a child's phone")
                }
                Button("Sync") { Task { await nearby.sync(phone, shelf: model.shelf, guardian: model.profiles.guardian) } }
                    .font(.system(size: 11))
                    .help("Open the app on \(phone.name) so it fetches what has been sent")
            }
        }
    }

    private func statusText(_ phone: PhoneDeployer.Phone) -> String? {
        switch nearby.status[phone.id] {
        case .syncing: "syncing…"
        case .synced(let at): "synced \(at.formatted(date: .omitted, time: .shortened))"
        case .failed(let why): why
        case nil: nil
        }
    }

    private func isFailed(_ phone: PhoneDeployer.Phone) -> Bool {
        if case .failed = nearby.status[phone.id] { true } else { false }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Palette.ink(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }
}
