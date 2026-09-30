import SwiftUI
import UIKit

/// The Home Screen quick actions: the menu a long press on the app icon opens, above
/// Edit Home Screen and Remove App.
///
/// The items themselves are static, in `UIApplicationShortcutItems` in project.yml. This
/// is only where a chosen one lands. SwiftUI has no hook for them, so it takes a UIKit
/// app and scene delegate: the scene delegate hears an action that arrives while the app
/// is running, and `willConnectTo` the one that launched it cold.
@Observable
@MainActor
final class QuickActions {
    static let shared = QuickActions()

    enum Action: String {
        case changeTheme = "com.d4vid4nderson.ytchannelscraper.changeTheme"
    }

    /// Set when an action arrives, cleared by whoever acts on it.
    var pending: Action?

    fileprivate func receive(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = Action(rawValue: item.type) else { return false }
        pending = action
        return true
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let item = connectionOptions.shortcutItem else { return }
        MainActor.assumeIsolated { _ = QuickActions.shared.receive(item) }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let handled = MainActor.assumeIsolated { QuickActions.shared.receive(shortcutItem) }
        completionHandler(handled)
    }
}
