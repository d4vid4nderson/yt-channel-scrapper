import SwiftUI
import AppKit
import AVFoundation

@main
struct YTChannelScraperApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        // No title bar: the traffic lights float over the page and the app's own
        // header is the only chrome.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1020, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Downloads") { model.showDownloads.toggle() }
                    .keyboardShortcut("j", modifiers: .command)
                Divider()
                Button("Open Downloads Folder") { NSWorkspace.shared.open(Paths.downloads) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Check for yt-dlp Updates…") {
                    model.showDownloads = true
                    Task { await model.updater.check() }
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// A single-window utility has nothing to stay open for once its window is gone.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private var appearanceWatch: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        applyIcon()
        // The bundle's .icns can only carry one appearance, so the running app swaps its
        // own Dock icon instead — and keeps swapping if the system flips mode while it
        // is open. At rest macOS still shows the dark .icns; an appearance-aware icon on
        // disk needs an Icon Composer .icon document, which has no build-time CLI.
        // Reads the appearance inside the callback and passes a plain Bool across, so
        // no non-Sendable self is captured by the @Sendable KVO closure.
        appearanceWatch = NSApp.observe(\.effectiveAppearance) { _, _ in
            // The appearance is read back on the main actor rather than inside this
            // @Sendable closure, which may not touch main-actor state.
            Task { @MainActor in
                AppDelegate.setIcon(
                    dark: NSApp.effectiveAppearance
                        .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                )
            }
        }
    }

    @MainActor
    private func applyIcon() {
        Self.setIcon(dark: NSApp.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    @MainActor
    fileprivate static func setIcon(dark isDark: Bool) {
        let name = isDark ? "AppIconDark" : "AppIconLight"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            Log.icon.error("missing \(name, privacy: .public).png in the bundle")
            return
        }
        NSApp.applicationIconImage = image
        Log.icon.info("applied \(name, privacy: .public)")
    }
}


