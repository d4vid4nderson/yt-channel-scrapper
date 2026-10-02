import CoreText
import SwiftUI

@main
struct YTScraperApp: App {
    /// Only for the Home Screen quick actions — see `QuickActions`.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The themes' bundled typefaces, registered for this process before any view asks
    /// for one, as the Mac app does.
    init() {
        for url in (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // Downloads run on a background `URLSession`, which means the system may finish
        // one while this app is suspended and then relaunch it just to hand the results
        // over. Without this the app has nowhere to receive that and iOS logs a warning
        // about a session with no handler; with it, `Transfer`'s delegate gets its
        // callbacks and the job finishes as if the app had been open all along.
        .backgroundTask(.urlSession(Transfer.sessionIdentifier)) {
            await Transfer.shared.discardOrphans()
        }
    }
}
