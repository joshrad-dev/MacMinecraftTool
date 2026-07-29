import Foundation
import IOKit
import IOKit.hidsystem

/// Flips the system "Use F1, F2, etc. keys as standard function keys"
/// behavior live via the IOHIDSystem service — the same mechanism the
/// open-source Fluor app uses. No Accessibility permission required.
///
/// The change takes effect immediately and lasts for the login session (it
/// does not rewrite the System Settings preference), so restoring the old
/// value on toggle-off/quit returns the machine to normal.
enum FunctionKeyManager {
    /// Reads the current fn-key mode. `true` = F1–F12 act as standard
    /// function keys, `false` = media/system keys. `nil` if unreadable.
    static func standardFunctionKeysEnabled() -> Bool? {
        guard let connect = openHIDSystem() else { return nil }
        defer { IOServiceClose(connect) }

        var value: Unmanaged<CFTypeRef>?
        let result = IOHIDCopyCFTypeParameter(connect, kIOHIDFKeyModeKey as CFString, &value)
        guard result == KERN_SUCCESS, let number = value?.takeRetainedValue() as? NSNumber else {
            return nil
        }
        return number.intValue != 0
    }

    @discardableResult
    static func setStandardFunctionKeys(_ enabled: Bool) -> Bool {
        guard let connect = openHIDSystem() else { return false }
        defer { IOServiceClose(connect) }

        let value = NSNumber(value: enabled ? 1 : 0)
        return IOHIDSetCFTypeParameter(connect, kIOHIDFKeyModeKey as CFString, value) == KERN_SUCCESS
    }

    private static func openHIDSystem() -> io_connect_t? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching(kIOHIDSystemClass)
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect)
        guard result == KERN_SUCCESS else { return nil }
        return connect
    }
}
