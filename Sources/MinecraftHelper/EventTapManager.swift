import AppKit
import CoreGraphics

/// Owns a single CGEventTap that implements the two mouse-related overrides:
///
/// - Ctrl+Click: strips the Control modifier flag from left-mouse events so
///   neither macOS nor the game converts the click into a right-click.
///   (Same approach as https://github.com/achendev/DisableCtrlClick)
/// - Shift+Scroll: strips the Shift modifier flag from scroll-wheel events so
///   the scroll is never reinterpreted as horizontal/reversed scrolling.
///   (Same trick LinearMouse uses in its ModifierActionsTransformer)
///
/// Keyboard events are untouched, so holding Ctrl or Shift still works for
/// sprint/sneak — only the flags carried on mouse events are modified.
final class EventTapManager {
    static let shared = EventTapManager()

    var stripCtrlFromClicks = false { didSet { rebuildTap() } }
    var stripShiftFromScroll = false { didSet { rebuildTap() } }

    /// False when a tap was wanted but could not be created (usually a
    /// missing Accessibility permission).
    private(set) var tapCreationFailed = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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
        return mask
    }

    private func rebuildTap() {
        teardownTap()
        tapCreationFailed = false

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
}

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
    default:
        break
    }

    return Unmanaged.passUnretained(event)
}
