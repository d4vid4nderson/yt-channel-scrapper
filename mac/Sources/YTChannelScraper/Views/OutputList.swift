import AVFoundation
import SwiftUI

/// Where this video's sound goes, as a list you tap — the way Control Center does it, and
/// the way the system route menu on macOS does not.
///
/// It opens inside the island rather than in a popover. The island is a borderless,
/// non-activating panel above the menu bar, and a popover hung off one of those has to
/// win a fight about window levels that it does not reliably win; growing the island
/// downward is the same move it already makes to expand, so it costs nothing and cannot
/// end up behind anything.
struct OutputList: View {
    let outputs: AudioOutputs
    let player: AVPlayer
    let dismiss: () -> Void
    let holdOpen: () -> Void
    let releaseHold: () -> Void

    @State private var hoveringAirPlay = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Output")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.leading, 8)
                .padding(.bottom, 3)

            ScrollView {
                VStack(spacing: 1) {
                    // The way back to "whatever the Mac is doing", which is where an
                    // untouched player already is — so it has to be a row you can return
                    // to, not just the state you started in.
                    OutputRow(
                        icon: "desktopcomputer",
                        name: "System default",
                        isSelected: outputs.selected == nil
                    ) {
                        outputs.select(nil, on: player)
                        dismiss()
                    }

                    ForEach(outputs.devices) { device in
                        OutputRow(
                            icon: device.icon,
                            name: device.name,
                            isSelected: outputs.selected == device.id
                        ) {
                            outputs.select(device.id, on: player)
                            dismiss()
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            Divider()
                .overlay(.white.opacity(0.12))
                .padding(.vertical, 4)

            airPlayRow
        }
    }

    /// The way to an Apple TV, a Roku, or another Mac.
    ///
    /// Those are not audio devices this Mac has — they are found by AirPlay discovery,
    /// which is the system's own and not open to us — so this row is the system picker,
    /// wearing the list's clothes. Drawn by us, clicked through to it.
    private var airPlayRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "airplayvideo")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.10)))
            Text("AirPlay to another device…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 8)
        .frame(height: MiniPlayer.outputRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(hoveringAirPlay ? 0.07 : 0))
        )
        .overlay {
            // Invisible, and on top: the system button fills this row, so the click that
            // looks like it is landing on our row is landing on the real picker.
            RoutePickerView(player: player, showsGlyph: false) { presenting in
                presenting ? holdOpen() : releaseHold()
            }
        }
        .onHover { hoveringAirPlay = $0 }
        .help("Apple TVs, Rokus and other Macs — found by the system, not listed above")
        .pointingHand()
        .animation(.easeOut(duration: 0.12), value: hoveringAirPlay)
    }
}

private struct OutputRow: View {
    let icon: String
    let name: String
    let isSelected: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.75))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(.white.opacity(isSelected ? 0.22 : 0.10))
                    )
                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 8)
            .frame(height: MiniPlayer.outputRowHeight)
            // One highlighted row, the way the system's own output list marks the live
            // one — a tick box next to every name would be saying you can have several,
            // and a player has exactly one output.
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.14 : (hovering ? 0.07 : 0)))
            )
        }
        .buttonStyle(.plain)
        .help(isSelected ? "\(name) — playing here now" : "Send this video's sound to \(name)")
        .pointingHand()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
