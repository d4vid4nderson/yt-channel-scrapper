import AVKit
import SwiftUI

/// The player, as a sheet over whatever list you started from.
///
/// The Mac has a resizable modal that can pop out into a floating window by the notch.
/// A phone has one screen, so this is a sheet — but it keeps the two things that
/// mattered: the stage is sized to the video's own aspect ratio, so a Short is not
/// letterboxed into a 16:9 box, and the resolving stages are named rather than hidden
/// behind an unexplained spinner.
struct PlayerSheet: View {
    @Bindable var model: AppModel
    let video: Video

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stage
                details
                Spacer(minLength: 0)
            }
            .ground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { close() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.download([video]) } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
        .onAppear { model.playback.open(video) }
        .onDisappear { model.playback.close() }
    }

    private func close() {
        model.playback.close()
        model.playing = nil
    }

    @ViewBuilder
    private var stage: some View {
        ZStack {
            Color.black
            switch model.playback.state {
            case .working(let stage):
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(stage)
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryText)
                }
            case .ready(let player):
                VideoPlayer(player: player)
            case .failed(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.secondaryText)
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondaryText)
                        .padding(.horizontal, 24)
                }
            }
        }
        .aspectRatio(model.playback.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(video.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primaryText)

            let meta = video.metaText(showingChannel: true)
            if !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }

            HStack(spacing: 10) {
                Button {
                    model.toggleSaved(video)
                } label: {
                    Label(model.isSaved(video) ? "Saved" : "Save",
                          systemImage: model.isSaved(video) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(model.isSaved(video) ? Palette.accent : Color.secondaryText)

                Button {
                    model.download([video])
                } label: {
                    Label(model.formatLabel, systemImage: "arrow.down.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.gutter)
    }
}
