import AppKit
import SwiftUI
import UserNotifications

@main
struct MinecraftHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Minecraft Helper") {
            ContentView()
                .environmentObject(OverridesModel.shared)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            MinecraftWatcher.shared.registerNotificationCategory()
            OverridesModel.shared.applyPersistedState()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            OverridesModel.shared.prepareForTermination()
        }
    }

    // Keep running with the window closed so overrides stay active while
    // playing; click the Dock icon to get the window back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
        if response.actionIdentifier == MinecraftWatcher.quitActionID {
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    // Show the quit prompt even when the app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
