import AppKit
import Foundation
import UserNotifications

/// Watches for a running Minecraft (Java) process. Once no such process has
/// been seen for a full minute, posts a notification offering to quit the
/// app. After the user dismisses/cancels it, the watcher stays quiet until
/// Minecraft is seen running again, so it never nags repeatedly.
@MainActor
final class MinecraftWatcher {
    static let shared = MinecraftWatcher()

    nonisolated static let quitActionID = "quit"
    nonisolated static let cancelActionID = "cancel"
    private static let categoryID = "quit-prompt"

    private static let pollInterval: TimeInterval = 5
    private static let absenceThreshold: TimeInterval = 60
    /// Requires "java" in the command line so the app itself (whose path
    /// contains "minecraft") never matches its own process.
    private static let processPattern = "java.*minecraft|minecraft.*java"

    private var timer: Timer?
    private var absenceStart: Date?
    private var armed = false
    private var checkInFlight = false

    func registerNotificationCategory() {
        let quit = UNNotificationAction(identifier: Self.quitActionID, title: "Quit", options: [.destructive])
        let cancel = UNNotificationAction(identifier: Self.cancelActionID, title: "Cancel", options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [quit, cancel],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func start(authorizationDenied: @escaping @MainActor () -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted {
                Task { @MainActor in authorizationDenied() }
            }
        }

        armed = true
        absenceStart = Date()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor in MinecraftWatcher.shared.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        absenceStart = nil
        armed = false
    }

    private func poll() {
        guard !checkInFlight else { return }
        checkInFlight = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-i", "-f", "-q", Self.processPattern]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { proc in
            let running = proc.terminationStatus == 0
            Task { @MainActor in
                let watcher = MinecraftWatcher.shared
                watcher.checkInFlight = false
                watcher.update(minecraftRunning: running)
            }
        }

        do {
            try process.run()
        } catch {
            checkInFlight = false
        }
    }

    private func update(minecraftRunning: Bool) {
        guard timer != nil else { return }

        if minecraftRunning {
            armed = true
            absenceStart = nil
            return
        }

        if absenceStart == nil {
            absenceStart = Date()
        }
        if armed, let start = absenceStart, Date().timeIntervalSince(start) >= Self.absenceThreshold {
            armed = false
            postQuitNotification()
        }
    }

    private func postQuitNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Minecraft Helper"
        content.body = "It seems like you're not playing Minecraft anymore, want to quit?"
        content.categoryIdentifier = Self.categoryID
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "quit-prompt-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
