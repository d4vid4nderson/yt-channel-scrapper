import AppKit
import Combine
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Namespace private var hero

    /// The hero holds the whole window until there is something to show, then collapses
    /// to a header — the same move the web app made, and for the same reason: the search
    /// is the whole app until it isn't.
    private var collapsed: Bool { model.hasResults }

    /// One easing for the entire landing -> app transition, matching the web app's
    /// `cubic-bezier(.4, 0, .2, 1)` over .65s.
    private static let morph = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.65)

    var body: some View {
        GeometryReader { geo in
            // One number drives the whole transition: the header's height. The results
            // are offset by exactly that, so they are revealed from underneath as it
            // shrinks rather than being covered by it — one motion, not two.
            let headerHeight = collapsed ? Layout.headerHeight : geo.size.height

            ZStack(alignment: .top) {
                resultsArea
                    .frame(
                        width: geo.size.width,
                        height: max(geo.size.height - Layout.headerHeight, 0)
                    )
                    .offset(y: headerHeight)

                header(height: headerHeight)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        // With the title bar hidden the window still insets its content below where the
        // bar used to be, leaving an unpainted strip above the header. The page owns the
        // whole window instead, and the traffic lights float on top of it.
        .ignoresSafeArea()
        .animation(Self.morph, value: collapsed)
        .frame(minWidth: 860, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willMiniaturizeNotification)) { _ in
            // Minimising should not stop what you are watching.
            model.popOutToIsland()
        }
        .task {
            // One quiet check per launch: yt-dlp ages out of working every few weeks,
            // and the failure it causes looks like a broken app rather than stale tool.
            await model.updater.refreshCurrent()
            await model.updater.check()
        }
        .overlay(alignment: .bottom) {
            // The handle sits on the edge the drawer rises from, so the gesture reads
            // as pulling the panel up rather than pressing an unrelated button.
            if !model.showDownloads {
                DownloadsHandle(count: model.downloader.activeCount) {
                    model.showDownloads = true
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.28), value: model.showDownloads)
        .overlay {
            PreviewModal(
                session: model.preview,
                download: { model.download([$0]) },
                popOut: { model.popOutToIsland() }
            )
        }
        .overlay {
            DownloadsDrawer(
                downloader: model.downloader,
                updater: model.updater,
                isPresented: $model.showDownloads
            )
        }
    }

    /// Always mounted, so its offset can animate. Off-screen below the hero until the
    /// header collapses and lifts it into view.
    private var resultsArea: some View {
        VStack(spacing: 0) {
            Divider()
            if let error = model.scraper.error, model.hasResults {
                ErrorBanner(message: error) { model.goHome() }
                Divider()
            }
            ResultsList(model: model)
        }
    }

    // MARK: - Header

    private func header(height: CGFloat) -> some View {
        ZStack {
            Palette.ground
            if !collapsed {
                AuroraBackground().transition(.opacity)
            }

            if collapsed {
                HStack(spacing: 10) {
                    HomeButton(action: model.goHome)
                        .matchedGeometryEffect(id: "brand", in: hero)
                    SearchPill(model: model, compact: true)
                        .matchedGeometryEffect(id: "pill", in: hero)
                }
                .padding(.horizontal, Layout.gutter)
                .frame(maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 16) {
                        BrandMark(width: 62)
                            .matchedGeometryEffect(id: "brand", in: hero)
                        Text("YT Channel Scraper")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                            .fixedSize()
                            .transition(.opacity)
                    }
                    SearchPill(model: model, compact: false)
                        .matchedGeometryEffect(id: "pill", in: hero)
                        .frame(maxWidth: 680)
                        .padding(.top, 46)
                    statusLine
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)   // sits the block a little above centre
                }
                .padding(.horizontal, 40)
            }
        }
        .frame(height: height)
        .clipped()
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            if model.scraper.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Reading the channel…")
                }
                .foregroundStyle(.white.opacity(0.75))
            } else if let error = model.scraper.error {
                Text(error)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.accent.opacity(0.9), in: RoundedRectangle(cornerRadius: 9))
            } else {
                Text("Pick the videos you want, download them in one go.")
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .font(.system(size: 13))
        .padding(.top, 22)
        .frame(height: 48, alignment: .top)
        .transition(.opacity)
    }
}

// MARK: - Chrome

/// The brand mark, which doubles as the way back to the landing view.
private struct HomeButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            BrandMark(width: 30)
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .help("Back to the start — the URL is kept")
        .pointingHand()
        .accessibilityLabel("Back to the start")
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// The tab peeking up from the bottom edge — the top lip of the drawer itself, so it
/// is obvious what pulling it does. Doubles as the progress indicator while closed.
private struct DownloadsHandle: View {
    let count: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .offset(y: hovering ? -1.5 : 0)
                Text("Downloads")
                    .font(.system(size: 12, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Palette.accent, in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: hovering ? 38 : 33)
            .background(Palette.sheetSurface)
            .clipShape(
                UnevenRoundedRectangle(topLeadingRadius: 13, topTrailingRadius: 13, style: .continuous)
            )
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 13, topTrailingRadius: 13, style: .continuous)
                    .strokeBorder(Color(white: 0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 14, y: -3)
        }
        .buttonStyle(.plain)
        .help(count > 0
              ? "Show the \(count) download\(count == 1 ? "" : "s") in progress  (⌘J)"
              : "Show downloads  (⌘J)")
        .pointingHand()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
    }
}

/// The one rounded bar holding the URL field, the tab menu and Scrape. It is the same
/// view in both states — that is what lets it travel rather than cut.
private struct SearchPill: View {
    @Bindable var model: AppModel
    let compact: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            ZStack(alignment: .leading) {
                if model.urlText.isEmpty {
                    Text("Paste a channel URL — youtube.com/@channelname, an @handle, or a playlist")
                        .foregroundStyle(.black.opacity(0.42))
                        .lineLimit(1)
                }
                TextField("", text: $model.urlText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.black)
                    .focused($focused)
                    .onSubmit { model.scrape() }
            }
            .font(.system(size: compact ? 13 : 14))
            .padding(.leading, compact ? 14 : 18)

            Menu {
                Picker("Type", selection: $model.tab) {
                    ForEach(ChannelTab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                // The borderless style draws no indicator over a custom background, and
                // it renders only a single Text — an HStack label comes out blank. So
                // the chevron is concatenated in, and each run carries its own colour
                // because a foregroundStyle on the Menu does not reach inside.
                Text(model.tab.label)
                    .font(.system(size: compact ? 12 : 13, weight: .medium))
                    .foregroundStyle(.black)
                    + Text("  ")
                    + Text(Image(systemName: "chevron.down"))
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                    .foregroundStyle(.black.opacity(0.55))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 5 : 8)
            .background(.white, in: Capsule())
            .help("Which tab of the channel to list")
            .pointingHand()

            Button {
                model.scraper.isBusy ? model.scraper.stop() : model.scrape()
            } label: {
                Text(model.scraper.isBusy ? "Stop" : "Scrape")
                    .font(.system(size: compact ? 12.5 : 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 66 : 78)
                    .padding(.vertical, compact ? 7 : 10)
                    .background(
                        Palette.accent.opacity(model.canScrape || model.scraper.isBusy ? 1 : 0.45),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.canScrape && !model.scraper.isBusy)
            .keyboardShortcut(.return, modifiers: [])
            .help(model.scraper.isBusy
                  ? "Stop reading this channel and keep what has been found"
                  : "List this channel's \(model.tab.label.lowercased())  (↩)")
            .pointingHand()
        }
        .padding(compact ? 5 : 7)
        .background(Color(white: 0.89), in: Capsule())
        .shadow(color: .black.opacity(compact ? 0.2 : 0.35), radius: compact ? 8 : 22, y: compact ? 3 : 8)
        // Landing on the hero, the one thing to do is type a URL.
        .onAppear { if !compact { focused = true } }
    }
}

private struct ErrorBanner: View {
    let message: String
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).lineLimit(2)
            Spacer(minLength: 8)
            Button("Start over", action: reset)
                .controlSize(.small)
                .help("Go back to the start, keeping the URL you typed")
                .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }
}

// MARK: - Results

private struct ResultsList: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView {
                // Cards, not list rows — they need the gap to read as separate surfaces.
                LazyVStack(spacing: 10) {
                    ForEach(model.visible) { video in
                        VideoRow(
                            video: video,
                            isPicked: model.picked.contains(video.id),
                            toggle: { model.toggle(video) },
                            downloadOne: { model.download([video]) },
                            preview: { model.preview.open(video) }
                        )
                    }

                    if model.scraper.canLoadMore && model.filterText.isEmpty {
                        Button("Load 25 more") { model.scraper.loadMore() }
                            .controlSize(.large)
                            .padding(.vertical, 10)
                            .help("Read the next 25 videos from this channel")
                            .pointingHand()
                    } else if model.visible.isEmpty {
                        Text("Nothing matches “\(model.filterText)”.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 56)   // clear of the downloads tab
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleAllVisible()
            } label: {
                HStack(spacing: 8) {
                    CheckBox(isOn: model.allVisiblePicked, size: 15)
                    Text("Select all").font(.system(size: 12.5))
                }
                .chip(active: model.allVisiblePicked)
            }
            .buttonStyle(.plain)
            .help(model.allVisiblePicked
                  ? "Untick every video currently listed"
                  : "Tick every video currently listed")
            .pointingHand()

            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField("Filter titles…", text: $model.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .frame(width: 150)
            }
            .chip()

            Text(countText)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            if model.scraper.isBusy {
                ProgressView().controlSize(.small)
            }

            // Quality and Download sit with the list they act on, the way the web app's
            // results bar had them, now that there is no window toolbar.
            Menu {
                Picker("Quality", selection: $model.quality) {
                    ForEach(Quality.menuOrder) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.quality.label).font(.system(size: 12.5))
                }
                .padding(.leading, 5)
                .padding(.trailing, 7)
                .padding(.vertical, 5)
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Which quality to fetch for the videos you pick")
            .pointingHand()

            Button {
                model.downloadPicked()
            } label: {
                Text(model.picked.isEmpty ? "Download" : "Download \(model.picked.count)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Palette.accent.opacity(model.picked.isEmpty ? 0.4 : 1),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.picked.isEmpty)
            .keyboardShortcut("d", modifiers: .command)
            .help(model.picked.isEmpty
                  ? "Tick some videos first, then download them here"
                  : "Download the \(model.picked.count) ticked video\(model.picked.count == 1 ? "" : "s") at \(model.quality.label)  (⌘D)")
            .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var countText: String {
        let total = model.scraper.videos.count
        let shown = model.visible.count
        var parts: [String] = []
        if !model.scraper.channel.isEmpty { parts.append(model.scraper.channel) }
        parts.append(shown == total ? "\(total) videos" : "\(shown) of \(total)")
        if !model.picked.isEmpty { parts.append("\(model.picked.count) selected") }
        return parts.joined(separator: "  ·  ")
    }
}
