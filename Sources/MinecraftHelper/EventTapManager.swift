import AppKit
import CoreGraphics

/// Owns a single CGEventTap that implements the input overrides:
///
/// - Ctrl+Click: strips the Control modifier flag from left-mouse events so
///   neither macOS nor the game converts the click into a right-click.
///   (Same approach as https://github.com/achendev/DisableCtrlClick)
/// - Shift+Scroll: strips the Shift modifier flag from scroll-wheel events so
///   the scroll is never reinterpreted as horizontal/reversed scrolling.
///   (Same trick LinearMouse uses in its ModifierActionsTransformer)
/// - Ctrl+Q drops a stack: on macOS the game's "control held" check looks at
///   the Command keys, and ⌘Q is the Quit menu shortcut. While Minecraft is
///   frontmost, Ctrl+Q gets a synthetic Command press wrapped around it, so
///   the game sees Command held while the Q event itself never carries the
///   Command flag that would trigger Quit.
///
/// Apart from the Q key in that one case, keyboard events are untouched, so
/// holding Ctrl or Shift still works for sprint/sneak.
final class EventTapManager {
    static let shared = EventTapManager()

    var stripCtrlFromClicks = false { didSet { rebuildTap() } }
    var stripShiftFromScroll = false { didSet { rebuildTap() } }
    var ctrlQDropsStack = false {
        didSet {
            updateFrontmostTracking()
            rebuildTap()
        }
    }

    /// False when a tap was wanted but could not be created (usually a
    /// missing Accessibility permission).
    private(set) var tapCreationFailed = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?

    fileprivate var minecraftIsFrontmost = false
    /// Set between the synthetic Command press and its release, so the
    /// release is sent even if Control or focus changes mid-press.
    fileprivate var holdingSyntheticCommand = false
    fileprivate let syntheticEventSource = CGEventSource(stateID: .privateState)

    private var desiredMask: CGEventMask {
        var mask: CGEventMask = 0
        if stripCtrlFromClicks {
            mask |= (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
                | (1 << CGEventType.leftMouseDragged.rawValue)
        }
        if stripShiftFromScroll {
            mask |= (1 << CGEventType.scrollWheel.rawValue)
        }
        if ctrlQDropsStack {
            mask |= (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
        }
        return mask
    }

    private func rebuildTap() {
        teardownTap()
        tapCreationFailed = false
        holdingSyntheticCommand = false

        let mask = desiredMask
        guard mask != 0 else { return }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            tapCreationFailed = true
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// The system disables taps that time out or that the user interrupts
    /// with Ctrl+Option+Cmd; turn them back on.
    func reenableTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func teardownTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.tap = nil
        }
    }

    // MARK: - Frontmost Minecraft tracking

    /// Cached on app activation so the tap callback never has to inspect
    /// processes itself.
    private func updateFrontmostTracking() {
        if ctrlQDropsStack {
            guard activationObserver == nil else { return }
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.minecraftIsFrontmost = app.map(Self.isMinecraft) ?? false
            }
            minecraftIsFrontmost = NSWorkspace.shared.frontmostApplication.map(Self.isMinecraft) ?? false
        } else {
            if let activationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
                self.activationObserver = nil
            }
            minecraftIsFrontmost = false
        }
    }

    /// The game runs as a bare `java` process (from whichever launcher), so
    /// match on its command line the same way the quit reminder does.
    private static func isMinecraft(_ app: NSRunningApplication) -> Bool {
        guard let commandLine = commandLine(of: app.processIdentifier) else { return false }
        return commandLine.range(
            of: MinecraftWatcher.processPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// KERN_PROCARGS2 layout: an Int32 argc, the exec path, NUL padding, then
    /// the NUL-separated argv (followed by the environment, which is skipped).
    private static func commandLine(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        return buffer[MemoryLayout<Int32>.size..<size]
            .split(separator: 0)
            .prefix(Int(argc) + 1)
            .map { String(decoding: $0, as: UTF8.self) }
            .joined(separator: " ")
    }
}

private let qKeyCode: Int64 = 0x0C
private let leftCommandKeyCode: CGKeyCode = 0x37

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let manager = EventTapManager.shared

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        manager.reenableTap()
    case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
        if manager.stripCtrlFromClicks, event.flags.contains(.maskControl) {
            event.flags.remove(.maskControl)
        }
    case .scrollWheel:
        if manager.stripShiftFromScroll, event.flags.contains(.maskShift) {
            event.flags.remove(.maskShift)
        }
    case .keyDown:
        if manager.ctrlQDropsStack,
           manager.minecraftIsFrontmost,
           !manager.holdingSyntheticCommand,
           event.getIntegerValueField(.keyboardEventKeycode) == qKeyCode,
           event.flags.contains(.maskControl),
           !event.flags.contains(.maskCommand),
           let commandDown = syntheticCommandEvent(flags: event.flags.union(.maskCommand), like: event),
           let q = event.copy() {
            manager.holdingSyntheticCommand = true
            // Swallow the original and re-post it after the Command press so
            // the order the game sees is guaranteed.
            commandDown.tapPostEvent(proxy)
            q.tapPostEvent(proxy)
            return nil
        }
    case .keyUp:
        if manager.holdingSyntheticCommand,
           event.getIntegerValueField(.keyboardEventKeycode) == qKeyCode,
           let q = event.copy() {
            manager.holdingSyntheticCommand = false
            q.tapPostEvent(proxy)
            if let commandUp = syntheticCommandEvent(flags: event.flags.subtracting(.maskCommand), like: event) {
                commandUp.tapPostEvent(proxy)
            }
            return nil
        }
    default:
        break
    }

    return Unmanaged.passUnretained(event)
}

/// A left-Command flagsChanged event. GLFW decides press vs. release from
/// whether the Command flag is set on it.
private func syntheticCommandEvent(flags: CGEventFlags, like original: CGEvent) -> CGEvent? {
    guard let event = CGEvent(
        keyboardEventSource: EventTapManager.shared.syntheticEventSource,
        virtualKey: leftCommandKeyCode,
        keyDown: true
    ) else { return nil }
    event.type = .flagsChanged
    event.flags = flags
    event.timestamp = original.timestamp
    return event
}
