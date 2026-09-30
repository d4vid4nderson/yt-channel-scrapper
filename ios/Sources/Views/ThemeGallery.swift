import SwiftUI

/// Every theme as the app icon it brings, to tap one. Opened by the Home Screen's
/// Change Theme quick action, so it is what someone who long-pressed the icon expects
/// to see: icons.
///
/// Open to a minor as much as to a parent, like the theme menu in Minor Mode — the theme
/// is per phone and changes nothing a parent decided.
struct ThemeGallery: View {
    let onPick: (Theme.ID) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(Theme.all) { theme in
                        tile(theme)
                    }
                }
                .padding(Metrics.gutter)
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func tile(_ theme: Theme) -> some View {
        let current = theme.id == ThemeStore.shared.selection
        return Button { onPick(theme.id) } label: {
            VStack(spacing: 8) {
                Image("ThemeIcon-\(theme.id.rawValue)")
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 72, height: 72)
                    // The Home Screen's own squircle, not a themed container: this is a
                    // picture of an app icon.
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .overlay {
                        if current {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Palette.accent, lineWidth: 3)
                        }
                    }
                Text(theme.name)
                    .font(.system(size: 12, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? Palette.accent : Color.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}
