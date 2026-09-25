import SwiftUI

/// The parent's side of the lock: set the PIN, see exactly what the minor will get, and
/// hand the phone over.
///
/// Deliberately explicit about what Minor Mode does and does not cover. It takes away the
/// Search tab and the ability to download, which is the whole of the problem on this
/// app's own screens — but it is a switch inside one app, not a restriction on the
/// phone, so it says so rather than letting anyone assume otherwise.
struct MinorModeView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// Which full-screen PIN flow is up, if any.
    @State private var flow: PINPad.Purpose?
    @State private var confirmingRemoval = false
    /// Which child this phone is about to become. Nil until picked — locking without an
    /// answer would leave the device holding no shelf at all.
    @State private var chosenMinor: Profiles.Minor?
    /// Set when `lock()` could not write the mode down. Never seen on a healthy phone,
    /// and the one case where silently carrying on would hand the minor an app that
    /// unlocks itself at the next launch.
    @State private var couldNotLock = false

    private var profiles: Profiles { model.profiles }

    var body: some View {
        NavigationStack {
            List {
                explanation
                if profiles.hasPIN {
                    handOver
                    pin
                } else {
                    setUp
                }
                transfer
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ground()
            .navigationTitle("Minor Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $flow) { purpose in
                PINPad(profiles: profiles,
                       purpose: purpose,
                       onDone: { flow = nil },
                       onCancel: { flow = nil })
            }
            .alert("Minor Mode could not be turned on", isPresented: $couldNotLock) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This phone would not save the setting, so it would come back off "
                     + "the next time the app opens. Restarting the phone usually "
                     + "clears this.")
            }
            .alert("Remove the PIN?", isPresented: $confirmingRemoval) {
                Button("Remove", role: .destructive) { profiles.forgetPIN() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Minor Mode will be turned off and the app goes back to having no "
                     + "modes at all. You can set a new PIN any time.")
            }
        }
    }

    // MARK: - Sections

    private var explanation: some View {
        Section {
            Row(icon: "house", title: "Home stays",
                detail: "Your saved channels and videos, and everything inside them.")
            Row(icon: "magnifyingglass.circle", title: "Search goes",
                detail: "The tab is gone. There is no field to type a channel or a "
                    + "video name into.")
            Row(icon: "arrow.down.circle", title: "Downloading goes",
                detail: "Finished files still play. Nothing new can be started, "
                    + "cancelled or deleted.")
            Row(icon: "bookmark", title: "Bookmarking stays",
                detail: "They can keep a video to the Videos shelf, and take it off "
                    + "again. Your channels cannot be removed.")
        } header: {
            header("What changes")
        } footer: {
            // The honest boundary. A parent should know where this ends before they
            // rely on it, not after.
            Text("Videos play in this app's own player, so there are no suggestions, "
                 + "no comments and nothing to tap through to. This is a switch inside "
                 + "this app though — it does not stop anyone using Safari or YouTube "
                 + "itself. Screen Time is what does that.")
        }
    }

    private var setUp: some View {
        Section {
            Button {
                flow = .create
            } label: {
                Label("Set a PIN", systemImage: "lock")
                    .font(.system(size: 15, weight: .medium))
            }
            .listRowBackground(Color.card)
        } footer: {
            Text("Four digits, and the only way back out of Minor Mode. Set it before "
                 + "handing the phone over.")
        }
    }

    @ViewBuilder
    private var handOver: some View {
        Section {
            if let last = profiles.lastMinor {
                // The usual case on a child's phone: it was theirs a minute ago.
                Button {
                    guard profiles.relock() else {
                        couldNotLock = true
                        return
                    }
                    model.enterMinorMode()
                    dismiss()
                } label: {
                    Label("Lock again for \(last.name)", systemImage: "lock.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .listRowBackground(Color.card)
            }
            if model.shelf.roster.isEmpty && profiles.lastMinor != nil {
                // Nothing else to offer until the family folder is connected.
            } else if model.shelf.roster.isEmpty {
                // Nothing to hand over yet. Said plainly rather than offering a disabled
                // button with no explanation of what would enable it.
                Row(icon: "person.crop.circle.badge.plus",
                    title: "Add a child first",
                    detail: "Settings → Family. Minor Mode needs to know whose shelf "
                        + "this phone is showing.")
            } else {
                Picker(selection: $chosenMinor) {
                    Text("Choose…").tag(Profiles.Minor?.none)
                    ForEach(model.shelf.roster, id: \.id) { minor in
                        Text(minor.name).tag(Profiles.Minor?.some(minor))
                    }
                } label: {
                    Label("This phone is", systemImage: "person.crop.circle")
                }
                .tint(Palette.accent)
                .listRowBackground(Color.card)

                Button {
                    guard let chosenMinor, profiles.lock(as: chosenMinor) else {
                        couldNotLock = true
                        return
                    }
                    model.enterMinorMode()
                    dismiss()
                } label: {
                    Label("Turn on Minor Mode", systemImage: "lock.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(chosenMinor == nil ? Color.secondaryText : Palette.accent)
                }
                .disabled(chosenMinor == nil)
                .listRowBackground(Color.card)
            }
        } footer: {
            Text("Takes effect straight away and survives closing the app, restarting "
                 + "the phone, and deleting and reinstalling the app. The phone will "
                 + "only show what both of you have approved for whoever you pick.")
        }
    }

    private var pin: some View {
        Section {
            Button {
                flow = .change
            } label: {
                Label("Change PIN", systemImage: "lock.rotation")
            }
            .listRowBackground(Color.card)

            if let name = profiles.biometryName {
                Toggle(isOn: Binding(get: { profiles.useFaceID },
                                     set: { profiles.setUseFaceID($0) })) {
                    Label("Unlock with \(name)", systemImage: "faceid")
                }
                .tint(Palette.accent)
                .listRowBackground(Color.card)
            }

            Button(role: .destructive) {
                confirmingRemoval = true
            } label: {
                Label("Remove PIN", systemImage: "lock.open")
            }
            .listRowBackground(Color.card)
        } header: {
            header("PIN")
        } footer: {
            if profiles.biometryName != nil {
                // The trap worth spelling out: on the minor's own phone, the enrolled
                // face is theirs, not yours. Leaving this off is the right default and the
                // reason it is off.
                Text("Leave this off if the face or fingerprint registered on this "
                     + "phone is theirs rather than yours, it would let them out of "
                     + "Minor Mode. "
                     + "Turn it on only when the device is yours.")
            }
        }
    }

    private var transfer: some View {
        Section {
            Row(icon: "square.and.arrow.up", title: "Export from your phone",
                detail: "Home → ⋯ → Export Library, then pick channels, videos or "
                    + "both. AirDrop the file over.")
            Row(icon: "tray.and.arrow.down", title: "Import on theirs",
                detail: "Home → ⋯ → Import Library, before you turn Minor Mode on. It "
                    + "says what is in the file and you choose what to take.")
        } header: {
            header("Getting your channels onto their phone")
        } footer: {
            Text("Exporting videos only is the tighter option: it sends a specific set "
                 + "of things to watch without also handing over every channel they "
                 + "came from. Importing merges rather than replaces, so sending an "
                 + "updated file later adds what is new and leaves the rest alone.")
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .textCase(nil)
    }

    /// An icon, a line, and the sentence under it. Four of these are the explanation,
    /// and a `Label` with a two-line subtitle is not a thing `List` does on its own.
    private struct Row: View {
        let icon: String
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24, alignment: .center)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.primaryText)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 3)
            .listRowBackground(Color.card)
        }
    }
}

/// Lets `PINPad.Purpose` drive `.fullScreenCover(item:)`.
extension PINPad.Purpose: Identifiable {
    var id: Int {
        switch self {
        case .unlock: return 0
        case .create: return 1
        case .change: return 2
        }
    }
}
