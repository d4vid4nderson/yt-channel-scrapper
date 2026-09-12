import SwiftUI

/// One video in a list.
///
/// The Mac's row is built around a pointer: a checkbox that appears on hover, a row that
/// lights up under the cursor, actions that reveal themselves. None of that survives on
/// a phone, so the interaction is rebuilt rather than translated — tap plays, a swipe
/// saves or downloads, and the checkbox only exists once you are selecting.
struct VideoRow: View {
    let video: Video
    var isPicked = false
    var isSelecting = false
    var isSaved = false
    var showChannel = false

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(isPicked ? Palette.accent : Color.secondaryText)
                    .transition(.scale.combined(with: .opacity))
            }

            Thumbnail(video: video)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                let meta = video.metaText(showingChannel: showChannel)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSaved {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// One channel: a search hit, or a saved favourite.
struct ChannelRow: View {
    let channel: Channel
    var isSaved = false

    var body: some View {
        HStack(spacing: 12) {
            Avatar(channel: channel, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                let subtitle = channel.subtitle
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSaved {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// The header above a channel's videos: who it is, and whether it is starred.
struct ChannelHeader: View {
    let channel: Channel
    let isSaved: Bool
    let onToggleSaved: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Avatar(channel: channel, size: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                let subtitle = channel.subtitle
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onToggleSaved) {
                Image(systemName: isSaved ? "star.fill" : "star")
                    .font(.system(size: 17))
                    .foregroundStyle(isSaved ? Palette.accent : Color.secondaryText)
                    .tappable()
            }
            .accessibilityLabel(isSaved ? "Remove from saved channels" : "Save channel")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
    }
}

/// The Videos / Shorts / Live / Music picker.
///
/// A segmented control rather than the Mac's chip row: four fixed options is exactly
/// what a segmented control is for, and it is the control an iOS user already knows.
struct TabPicker: View {
    @Binding var tab: ChannelTab

    var body: some View {
        Picker("Type", selection: $tab) {
            ForEach(ChannelTab.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Metrics.gutter)
    }
}
