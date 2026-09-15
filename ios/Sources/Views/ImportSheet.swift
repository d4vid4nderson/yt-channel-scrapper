import SwiftUI

/// What is in the file you just picked, and how much of it you want.
///
/// Shown after the document picker rather than before it, which is the whole point: a
/// menu that asks "channels or videos?" up front is asking you to guess what a file
/// contains. This has read it, so it can say — and it offers only the halves that are
/// actually in there.
struct ImportSheet: View {
    @Bindable var model: AppModel
    let pending: AppModel.PendingImport

    @State private var contents: Library.Contents
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, pending: AppModel.PendingImport) {
        self.model = model
        self.pending = pending
        // Default to everything the file has. When it only holds one of the two, that
        // one — a picker whose first option is "Both" over a channels-only file would
        // be offering something that does not exist.
        _contents = State(initialValue: Self.choices(in: pending.archive).first ?? .both)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Channels", value: "\(pending.archive.channels.count)")
                        .listRowBackground(Color.card)
                    LabeledContent("Videos", value: "\(pending.archive.videos.count)")
                        .listRowBackground(Color.card)
                } header: {
                    header("In this file")
                } footer: {
                    Text(pending.filename)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondaryText)
                }

                if choices.count > 1 {
                    Section {
                        Picker("Import", selection: $contents) {
                            ForEach(choices) { Text($0.short).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } header: {
                        header("Take")
                    }
                }

                Section {
                    Button {
                        model.takeImport(contents)
                        dismiss()
                    } label: {
                        Label("Import", systemImage: "tray.and.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    .disabled(isEmpty)
                    .listRowBackground(Color.card)
                } footer: {
                    Text(isEmpty
                         ? "There is nothing in this file to import."
                         : "Merges rather than replaces. Anything already here is left "
                            + "alone, so importing the same file twice changes nothing.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ground()
            .navigationTitle("Import Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        model.pendingImport = nil
                        dismiss()
                    }
                }
            }
        }
    }

    private var choices: [Library.Contents] { Self.choices(in: pending.archive) }

    private var isEmpty: Bool {
        pending.archive.channels.isEmpty && pending.archive.videos.isEmpty
    }

    /// Only the options this particular file can actually satisfy. A file with channels
    /// and no videos offers one choice, and the picker then does not appear at all.
    private static func choices(in archive: LibraryArchive) -> [Library.Contents] {
        let hasChannels = !archive.channels.isEmpty
        let hasVideos = !archive.videos.isEmpty
        switch (hasChannels, hasVideos) {
        case (true, true):  return [.both, .channels, .videos]
        case (true, false): return [.channels]
        case (false, true): return [.videos]
        case (false, false): return []
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .textCase(nil)
    }
}
