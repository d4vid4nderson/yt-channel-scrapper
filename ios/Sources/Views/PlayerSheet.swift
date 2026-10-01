import AVKit
import SwiftUI
import UIKit

/// The player, as a sheet over whatever list you started from.
///
/// The Mac has a resizable modal that can pop out into a floating window by the notch.
/// A phone has one screen, so this is a sheet — but it keeps the two things that
/// mattered: the stage is sized to the video's own aspect ratio, so a Short is not
/// letterboxed into a 16:9 box, and the resolving stages are named rather than hidden
/// behind an unexplained spinner.
///
/// It takes a `Playable` rather than a `Video` because a file already on the phone plays
/// through the same stage and the same transport. What differs is only what you can do
/// with it underneath: a stream can be saved or downloaded, a local file can be shared.
struct PlayerSheet: View {
    @Bindable var model: AppModel
    let item: Playable

    @State private var sharing: URL?

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
                    // Closes the screen, not the sound — the bar above the tabs keeps
                    // playing and is the way back in.
                    Button("Close") { close() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Both of these are ways for a file to start or leave — neither is
                    // the minor's, so in Minor Mode the corner is simply empty.
                    if model.isMinor {
                        EmptyView()
                    } else if item.video != nil {
                        DownloadButton(job: job, action: downloadTapped)
                    } else if let file = item.file {
                        Button { sharing = file.url } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(item: $sharing) { url in
                ShareSheet(items: [url])
            }
        }
        .onAppear { model.resume(item) }
        // Also the swipe down, which is how most people close a sheet. Leaving is not
        // stopping: what is playing carries on in the bar above the tabs.
        .onDisappear { model.playback.leave() }
    }

    private func close() { model.leavePlayer() }

    /// Leave the player and push the channel onto whichever tab is in front.
    private func open(_ channel: Channel) {
        model.leavePlayer()
        model.show(channel)
    }

    /// The job for this video, if one has been queued. The most recent, because a
    /// failed attempt leaves its job in the list and a retry adds another.
    private var job: DownloadJob? {
        guard let id = item.video?.id else { return nil }
        return model.downloads.jobs.last { $0.video.id == id }
    }

    /// One button, so the tap has to mean whatever the job needs next.
    private func downloadTapped() {
        guard let video = item.video else { return }
        guard let job else {
            model.download([video])
            return
        }
        switch job.state {
        case .downloading, .queued, .retrying:
            model.downloads.pause(job)
        case .paused:
            model.downloads.resume(job)
        case .done:
            // "Open the downloads" means the app's own list of what is on the phone,
            // not Files.app: it is one tap away, always works, and is the same folder.
            // The video comes with you, playing, in the bar above the tabs.
            model.leavePlayer()
            model.tab = .downloads
        case .failed, .cancelled:
            model.download([video])
        case .processing:
            break   // mid-mux, and nothing useful can be done to it
        }
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
                // An m4a has no picture of its own, and without one this is a black
                // rectangle with a scrubber on it — which reads as a video that failed
                // to load rather than as audio.
                Stage(player: player, poster: item.isVideo ? nil : item.artwork)
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
            Text(item.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primaryText)

            // The channel is a way in, not just a label: finding a video is often how
            // you find the channel worth keeping, and this is where you are when you
            // decide that.
            if let video = item.video, let channel = model.channel(of: video) {
                HStack(spacing: 6) {
                    Button { open(channel) } label: {
                        HStack(spacing: 3) {
                            Text(channel.title)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)

                    if !video.viewsText.isEmpty {
                        Text("·  \(video.viewsText)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondaryText)
                    }
                }
            } else if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }

            HStack(spacing: 10) { actions }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.gutter)
    }

    @ViewBuilder
    private var actions: some View {
        repeatButton
        if let video = item.video {
            // Bookmarking is the one thing a minor can add to the library, and it is
            // theirs to undo: the same button takes it off again.
            Button {
                model.toggleSaved(video)
            } label: {
                Label(model.isSaved(video) ? "Saved" : "Save",
                      systemImage: model.isSaved(video) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(model.isSaved(video) ? Palette.accent : Color.secondaryText)

            if !model.isMinor {
                Button {
                    model.download([video])
                } label: {
                    Label(model.formatLabel, systemImage: "arrow.down.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                // The theme sets a default ink for the whole app, which would otherwise win over
                // the white a filled button gives its label — green on green on the Nostromo.
                .foregroundStyle(Palette.onFill)
                .tint(Palette.accent)
            }
        } else if let file = item.file {
            if !model.isMinor {
                Button {
                    sharing = file.url
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                // The theme sets a default ink for the whole app, which would otherwise win over
                // the white a filled button gives its label — green on green on the Nostromo.
                .foregroundStyle(Palette.onFill)
                .tint(Palette.accent)
            }

            Text("On this phone")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondaryText)
        }
    }

    /// Off, this video, or its channel — one button, round the three. Open to a minor:
    /// looping the channel only ever moves through what was approved.
    private var repeatButton: some View {
        let setting = RepeatSetting.shared
        return Button {
            setting.mode = setting.mode.next
        } label: {
            Image(systemName: setting.mode.symbol)
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .tint(setting.mode == .off ? Color.secondaryText : Palette.accent)
        .accessibilityLabel(setting.mode.label)
    }
}

/// `AVPlayerViewController`, wrapped, rather than SwiftUI's `VideoPlayer`.
///
/// `VideoPlayer` is this same controller underneath, but it exposes no way to turn off
/// `updatesNowPlayingInfoCenter`, which defaults to on. AVKit then writes the lock screen
/// entry itself, from whatever metadata the file carries — a downloaded mp4 carries none
/// — at the same time as `NowPlaying` is writing the real title and poster, and the user
/// sees whichever of the two wrote last. That surface needs exactly one owner, so AVKit
/// is told to leave it alone.
struct Stage: UIViewControllerRepresentable {
    let player: AVPlayer
    /// Drawn behind the transport controls when the item has no picture of its own.
    var poster: URL?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.updatesNowPlayingInfoCenter = false
        // Touching `view` forces the controller to load, which is what makes
        // `contentOverlayView` exist to hang the poster on.
        controller.view.backgroundColor = .black
        if let poster { context.coordinator.show(poster, in: controller) }
        // Swiping home with the player open floats the video over the Home Screen rather
        // than leaving only its sound — the nearest iOS comes to a video widget, since a
        // widget is a drawing and cannot hold a player. The widgets' controls drive the
        // same player, so they work on the floating one too. AVKit's own PiP, by choice:
        // a themed one (an accent frame drawn onto every frame) was built and taken out
        // again, because a frame round the picture distracts from the video.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Holds the poster fetch, so it is cancelled with the view rather than outliving it.
    @MainActor
    final class Coordinator {
        private var task: Task<Void, Never>?

        deinit { task?.cancel() }

        /// `contentOverlayView` is AVKit's own slot for this: above the video surface,
        /// below the transport controls. Anything layered over the controller in SwiftUI
        /// instead would sit on top of the controls and swallow them.
        ///
        /// The opaque backdrop is not padding. On an audio-only item AVKit draws its own
        /// placeholder — a speaker with sound waves — into the empty video surface, and
        /// a poster laid over that lands in the middle of it. Filling the overlay hides
        /// the placeholder so there is one picture on screen instead of two.
        func show(_ url: URL, in controller: AVPlayerViewController) {
            guard let overlay = controller.contentOverlayView else { return }

            let backdrop = UIView()
            backdrop.backgroundColor = .black
            backdrop.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(backdrop)

            let image = UIImageView()
            image.contentMode = .scaleAspectFit
            image.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(image)

            NSLayoutConstraint.activate([
                backdrop.topAnchor.constraint(equalTo: overlay.topAnchor),
                backdrop.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
                backdrop.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
                backdrop.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),

                image.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                image.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
                image.heightAnchor.constraint(equalTo: overlay.heightAnchor, multiplier: 0.7),
                image.widthAnchor.constraint(equalTo: overlay.widthAnchor, multiplier: 0.7),
            ])

            task = Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      !Task.isCancelled
                else { return }
                image.image = UIImage(data: data)
            }
        }
    }
}
