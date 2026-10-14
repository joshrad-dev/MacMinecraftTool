import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

// Private IOKit HID SPI — the same declarations LinearMouse ships in its
// PointerKitC module. The symbols are exported by IOKit.framework.
@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventSystemClientSetMatchingMultiple")
private func IOHIDEventSystemClientSetMatchingMultiple(_ client: CFTypeRef, _ matches: CFArray)

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: CFTypeRef, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientSetProperty")
private func IOHIDServiceClientSetProperty(_ service: CFTypeRef, _ key: CFString, _ value: CFTypeRef) -> Bool

/// Disables macOS pointer acceleration while active, restoring the previous
/// values on deactivate.
///
/// Two mechanisms are used together:
/// - Session-wide HID parameters on IOHIDSystem (`HIDMouseAcceleration` etc.),
///   the classic API and the layer we snapshot/restore from.
/// - Per-device properties via the private IOHIDEventSystemClient API —
///   `HIDUseLinearScalingMouseAcceleration` (the Sonoma+ switch LinearMouse
///   prefers) plus the device's acceleration-type key set to -1 (disabled).
///
/// A slow timer re-applies the override so newly plugged-in mice are covered
/// and system preference changes can't silently re-enable acceleration.
final class PointerAccelerationManager {
    static let shared = PointerAccelerationManager()

    private static let linearScalingKey = "HIDUseLinearScalingMouseAcceleration"
    private static let accelerationTypeKey = "HIDPointerAccelerationType"
    private static let systemAccelerationKeys = [
        "HIDMouseAcceleration",
        "HIDTrackpadAcceleration",
        "HIDPointerAcceleration"
    ]
    /// IOFixed encoding of -1.0: acceleration disabled.
    private static let disabledAcceleration = -65_536
    private static let snapshotKey = "pointerAccel.snapshot"
    /// Persisted while the override is applied, so a run that ends without
    /// `deactivate()` (crash, force quit) can be cleaned up at next launch.
    private static let activeKey = "pointerAccel.active"

    private var reapplyTimer: Timer?
    private let defaults = UserDefaults.standard

    private(set) var isActive = false

    /// `captureSnapshot` is false when re-asserting after a relaunch, so the
    /// snapshot taken at the original enable isn't overwritten with our own
    /// already-overridden values.
    @discardableResult
    func activate(captureSnapshot: Bool) -> Bool {
        if captureSnapshot || defaults.dictionary(forKey: Self.snapshotKey) == nil {
            defaults.set(readSystemParameters(), forKey: Self.snapshotKey)
        }

        let succeeded = apply()
        guard succeeded else { return false }

        isActive = true
        defaults.set(true, forKey: Self.activeKey)
        if reapplyTimer == nil {
            reapplyTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                self?.apply()
            }
        }
        return true
    }

    func deactivate() {
        reapplyTimer?.invalidate()
        reapplyTimer = nil
        guard isActive else { return }
        isActive = false
        restore()
        defaults.set(false, forKey: Self.activeKey)
    }

    /// Undo an override left applied by a previous run that never got to
    /// `deactivate()`. Acceleration is a system-wide setting that outlives the
    /// process, so without this it would stay disabled after a crash.
    func restoreIfLeftActive() {
        guard defaults.bool(forKey: Self.activeKey) else { return }
        restore()
        defaults.set(false, forKey: Self.activeKey)
    }

    // MARK: - Apply / restore

    @discardableResult
    private func apply() -> Bool {
        var anySucceeded = false

        withHIDSystemConnection { connect in
            for key in Self.systemAccelerationKeys {
                if IOHIDSetCFTypeParameter(connect, key as CFString, NSNumber(value: Self.disabledAcceleration)) == KERN_SUCCESS {
                    anySucceeded = true
                }
            }
            if IOHIDSetCFTypeParameter(connect, Self.linearScalingKey as CFString, NSNumber(value: 1)) == KERN_SUCCESS {
                anySucceeded = true
            }
        }

        for service in copyPointerServices() {
            if IOHIDServiceClientSetProperty(service, Self.linearScalingKey as CFString, NSNumber(value: 1)) {
                anySucceeded = true
            }
            let typeKey = accelerationTypeKey(for: service)
            if IOHIDServiceClientSetProperty(service, typeKey as CFString, NSNumber(value: Self.disabledAcceleration)) {
                anySucceeded = true
            }
        }

        return anySucceeded
    }

    private func restore() {
        guard let snapshot = defaults.dictionary(forKey: Self.snapshotKey) as? [String: Int] else {
            return
        }

        withHIDSystemConnection { connect in
            for (key, value) in snapshot {
                IOHIDSetCFTypeParameter(connect, key as CFString, NSNumber(value: value))
            }
        }

        for service in copyPointerServices() {
            if let linear = snapshot[Self.linearScalingKey] {
                _ = IOHIDServiceClientSetProperty(service, Self.linearScalingKey as CFString, NSNumber(value: linear))
            }
            let typeKey = accelerationTypeKey(for: service)
            if let value = snapshot[typeKey] {
                _ = IOHIDServiceClientSetProperty(service, typeKey as CFString, NSNumber(value: value))
            }
        }
    }

    private func readSystemParameters() -> [String: Int] {
        var parameters: [String: Int] = [:]
        withHIDSystemConnection { connect in
            for key in Self.systemAccelerationKeys + [Self.linearScalingKey] {
                var value: Unmanaged<CFTypeRef>?
                if IOHIDCopyCFTypeParameter(connect, key as CFString, &value) == KERN_SUCCESS,
                   let number = value?.takeRetainedValue() as? NSNumber {
                    parameters[key] = number.intValue
                }
            }
        }
        return parameters
    }

    // MARK: - HID plumbing

    private func withHIDSystemConnection(_ body: (io_connect_t) -> Void) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching(kIOHIDSystemClass)
        )
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else {
            return
        }
        defer { IOServiceClose(connect) }
        body(connect)
    }

    /// Created once and held for the lifetime of the process. The service
    /// clients handed out by `IOHIDEventSystemClientCopyServices` stay bound to
    /// the client that vended them: release it and the next
    /// `IOHIDServiceClientSetProperty` crashes inside IOKit's termination
    /// callback (`CFRelease() called with NULL`). LinearMouse likewise keeps
    /// its client alive in `PointerDeviceManager`.
    private lazy var eventSystemClient: CFTypeRef? = {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else {
            return nil
        }
        let matches = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer]
        ] as CFArray
        IOHIDEventSystemClientSetMatchingMultiple(client, matches)
        return client
    }()

    private func copyPointerServices() -> [CFTypeRef] {
        guard let client = eventSystemClient else { return [] }
        return IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [CFTypeRef] ?? []
    }

    private func accelerationTypeKey(for service: CFTypeRef) -> String {
        IOHIDServiceClientCopyProperty(service, Self.accelerationTypeKey as CFString)?
            .takeRetainedValue() as? String ?? "HIDMouseAcceleration"
    }
}
