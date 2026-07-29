import ApplicationServices
import Combine
import Foundation

@MainActor
final class OverridesModel: ObservableObject {
    static let shared = OverridesModel()

    @Published var ctrlClickOverride: Bool {
        didSet {
            defaults.set(ctrlClickOverride, forKey: Keys.ctrlClick)
            applyMouseOverrides()
        }
    }

    @Published var functionKeysOverride: Bool {
        didSet {
            defaults.set(functionKeysOverride, forKey: Keys.fnKeys)
            applyFunctionKeyOverride(enabled: functionKeysOverride)
        }
    }

    @Published var shiftScrollOverride: Bool {
        didSet {
            defaults.set(shiftScrollOverride, forKey: Keys.shiftScroll)
            applyMouseOverrides()
        }
    }

    @Published var pointerAccelOverride: Bool {
        didSet {
            defaults.set(pointerAccelOverride, forKey: Keys.pointerAccel)
            applyPointerAccelOverride(enabled: pointerAccelOverride)
        }
    }

    @Published var shakeOverride: Bool {
        didSet {
            defaults.set(shakeOverride, forKey: Keys.shake)
            applyShakeOverride(enabled: shakeOverride)
        }
    }

    @Published var quitReminderEnabled: Bool {
        didSet {
            defaults.set(quitReminderEnabled, forKey: Keys.quitReminder)
            applyQuitReminder(enabled: quitReminderEnabled)
        }
    }

    /// Whether each override is included in the master switch's sweep.
    /// Unchecked overrides are left alone when the master switch flips.
    @Published var ctrlClickIncluded: Bool {
        didSet { defaults.set(ctrlClickIncluded, forKey: Keys.ctrlClickIncluded) }
    }

    @Published var functionKeysIncluded: Bool {
        didSet { defaults.set(functionKeysIncluded, forKey: Keys.fnKeysIncluded) }
    }

    @Published var shiftScrollIncluded: Bool {
        didSet { defaults.set(shiftScrollIncluded, forKey: Keys.shiftScrollIncluded) }
    }

    @Published var pointerAccelIncluded: Bool {
        didSet { defaults.set(pointerAccelIncluded, forKey: Keys.pointerAccelIncluded) }
    }

    @Published var shakeIncluded: Bool {
        didSet { defaults.set(shakeIncluded, forKey: Keys.shakeIncluded) }
    }

    @Published var quitReminderIncluded: Bool {
        didSet { defaults.set(quitReminderIncluded, forKey: Keys.quitReminderIncluded) }
    }

    /// Not persisted: this is an action control, not a status readout, so it
    /// always starts unflipped rather than trying to reflect mixed states.
    @Published var masterSwitch = false {
        didSet {
            if ctrlClickIncluded { ctrlClickOverride = masterSwitch }
            if functionKeysIncluded { functionKeysOverride = masterSwitch }
            if shiftScrollIncluded { shiftScrollOverride = masterSwitch }
            if pointerAccelIncluded { pointerAccelOverride = masterSwitch }
            if shakeIncluded { shakeOverride = masterSwitch }
            if quitReminderIncluded { quitReminderEnabled = masterSwitch }
        }
    }

    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var functionKeyError: String?
    @Published private(set) var pointerAccelError: String?
    @Published private(set) var shakeNeedsFullDiskAccess = false
    @Published private(set) var notificationsDenied = false

    private let defaults = UserDefaults.standard
    private var permissionPollTimer: Timer?
    private var hasPromptedForAccessibility = false

    /// Whether the fn-key override is the one currently holding the system
    /// in "standard function keys" mode. Guards against re-capturing
    /// `Keys.savedFnMode` from `functionKeysOverride`'s didSet firing again
    /// while already on (e.g. the master switch reasserting `true`), which
    /// would read back our own override as if it were the user's original
    /// preference and clobber the real saved value.
    private var functionKeyOverrideIsActive = false

    /// Same guard pattern as `functionKeyOverrideIsActive`, for the shake
    /// override: prevents re-capturing `Keys.savedShakeValue` while the
    /// override is already holding the setting.
    private var shakeOverrideIsActive = false

    private enum Keys {
        static let ctrlClick = "override.ctrlClick"
        static let fnKeys = "override.fnKeys"
        static let shiftScroll = "override.shiftScroll"
        static let pointerAccel = "override.pointerAccel"
        static let shake = "override.shake"
        static let quitReminder = "override.quitReminder"
        static let savedFnMode = "override.fnKeys.savedMode"
        static let savedShakeValue = "override.shake.savedValue"
        static let ctrlClickIncluded = "override.ctrlClick.included"
        static let fnKeysIncluded = "override.fnKeys.included"
        static let shiftScrollIncluded = "override.shiftScroll.included"
        static let pointerAccelIncluded = "override.pointerAccel.included"
        static let shakeIncluded = "override.shake.included"
        static let quitReminderIncluded = "override.quitReminder.included"
    }

    private init() {
        ctrlClickOverride = defaults.bool(forKey: Keys.ctrlClick)
        functionKeysOverride = defaults.bool(forKey: Keys.fnKeys)
        shiftScrollOverride = defaults.bool(forKey: Keys.shiftScroll)
        pointerAccelOverride = defaults.bool(forKey: Keys.pointerAccel)
        shakeOverride = defaults.bool(forKey: Keys.shake)
        quitReminderEnabled = defaults.bool(forKey: Keys.quitReminder)
        ctrlClickIncluded = defaults.object(forKey: Keys.ctrlClickIncluded) == nil
            ? true : defaults.bool(forKey: Keys.ctrlClickIncluded)
        functionKeysIncluded = defaults.object(forKey: Keys.fnKeysIncluded) == nil
            ? true : defaults.bool(forKey: Keys.fnKeysIncluded)
        shiftScrollIncluded = defaults.object(forKey: Keys.shiftScrollIncluded) == nil
            ? true : defaults.bool(forKey: Keys.shiftScrollIncluded)
        pointerAccelIncluded = defaults.object(forKey: Keys.pointerAccelIncluded) == nil
            ? true : defaults.bool(forKey: Keys.pointerAccelIncluded)
        shakeIncluded = defaults.object(forKey: Keys.shakeIncluded) == nil
            ? true : defaults.bool(forKey: Keys.shakeIncluded)
        quitReminderIncluded = defaults.object(forKey: Keys.quitReminderIncluded) == nil
            ? true : defaults.bool(forKey: Keys.quitReminderIncluded)
        accessibilityGranted = AXIsProcessTrusted()
    }

    var needsAccessibility: Bool {
        (ctrlClickOverride || shiftScrollOverride) && !accessibilityGranted
    }

    /// Called once at launch to re-apply whatever was on last time.
    func applyPersistedState() {
        applyMouseOverrides()
        if functionKeysOverride {
            // Re-assert standard fn keys; the saved pre-override mode from
            // the original enable is still in defaults, so don't overwrite it.
            if FunctionKeyManager.setStandardFunctionKeys(true) {
                functionKeyOverrideIsActive = true
            } else {
                functionKeyError = "Couldn't change the function key mode."
            }
        }
        if pointerAccelOverride {
            // captureSnapshot: false — the snapshot from the original enable
            // is still in defaults and reflects the real pre-override values.
            if !PointerAccelerationManager.shared.activate(captureSnapshot: false) {
                pointerAccelError = "Couldn't change pointer acceleration."
            }
        }
        if shakeOverride {
            shakeNeedsFullDiskAccess = !ShakeToLocateManager.setShakeDisabled(true)
            shakeOverrideIsActive = !shakeNeedsFullDiskAccess
        }
        if quitReminderEnabled {
            applyQuitReminder(enabled: true)
        }
    }

    /// Called when the app is quitting: put the system back the way it was.
    func prepareForTermination() {
        if functionKeyOverrideIsActive {
            restoreSavedFunctionKeyMode()
            functionKeyOverrideIsActive = false
        }
        PointerAccelerationManager.shared.deactivate()
        if shakeOverrideIsActive {
            restoreSavedShakeValue()
            shakeOverrideIsActive = false
        }
        MinecraftWatcher.shared.stop()
        EventTapManager.shared.stripCtrlFromClicks = false
        EventTapManager.shared.stripShiftFromScroll = false
    }

    func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        hasPromptedForAccessibility = true
    }

    // MARK: - Mouse overrides (need Accessibility)

    private func applyMouseOverrides() {
        accessibilityGranted = AXIsProcessTrusted()

        if needsAccessibility {
            if !hasPromptedForAccessibility {
                promptForAccessibility()
            }
            startPollingForPermission()
        }

        let manager = EventTapManager.shared
        manager.stripCtrlFromClicks = ctrlClickOverride && accessibilityGranted
        manager.stripShiftFromScroll = shiftScrollOverride && accessibilityGranted
    }

    /// While a mouse override is switched on but permission hasn't been
    /// granted yet, poll so the tap starts the moment the user grants it.
    private func startPollingForPermission() {
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let model = OverridesModel.shared
                model.accessibilityGranted = AXIsProcessTrusted()
                guard model.accessibilityGranted || !(model.ctrlClickOverride || model.shiftScrollOverride) else {
                    return
                }
                model.permissionPollTimer?.invalidate()
                model.permissionPollTimer = nil
                model.applyMouseOverrides()
            }
        }
    }

    // MARK: - Function keys (no permission needed)

    private func applyFunctionKeyOverride(enabled: Bool) {
        functionKeyError = nil
        if enabled {
            guard !functionKeyOverrideIsActive else { return }
            // Remember what the user had before so toggling off restores it.
            let previous = FunctionKeyManager.standardFunctionKeysEnabled() ?? false
            defaults.set(previous, forKey: Keys.savedFnMode)
            if FunctionKeyManager.setStandardFunctionKeys(true) {
                functionKeyOverrideIsActive = true
            } else {
                functionKeyError = "Couldn't change the function key mode."
            }
        } else if functionKeyOverrideIsActive {
            restoreSavedFunctionKeyMode()
            functionKeyOverrideIsActive = false
        }
    }

    private func restoreSavedFunctionKeyMode() {
        let saved = defaults.bool(forKey: Keys.savedFnMode)
        FunctionKeyManager.setStandardFunctionKeys(saved)
    }

    // MARK: - Pointer acceleration (no permission needed)

    private func applyPointerAccelOverride(enabled: Bool) {
        pointerAccelError = nil
        if enabled {
            guard !PointerAccelerationManager.shared.isActive else { return }
            if !PointerAccelerationManager.shared.activate(captureSnapshot: true) {
                pointerAccelError = "Couldn't change pointer acceleration."
            }
        } else {
            PointerAccelerationManager.shared.deactivate()
        }
    }

    // MARK: - Shake to locate (needs Full Disk Access)

    private func applyShakeOverride(enabled: Bool) {
        if enabled {
            guard !shakeOverrideIsActive else { return }
            // Remember what the user had before so toggling off restores it.
            let previous = ShakeToLocateManager.currentValue()
            defaults.set(previous.rawValue, forKey: Keys.savedShakeValue)
            if ShakeToLocateManager.setShakeDisabled(true) {
                shakeNeedsFullDiskAccess = false
                shakeOverrideIsActive = true
            } else {
                shakeNeedsFullDiskAccess = true
            }
        } else {
            shakeNeedsFullDiskAccess = false
            if shakeOverrideIsActive {
                restoreSavedShakeValue()
                shakeOverrideIsActive = false
            }
        }
    }

    private func restoreSavedShakeValue() {
        let raw = defaults.object(forKey: Keys.savedShakeValue) as? Int ?? -1
        let saved = ShakeToLocateManager.SavedValue(rawValue: raw) ?? .absent
        ShakeToLocateManager.restore(saved)
    }

    // MARK: - Quit reminder

    private func applyQuitReminder(enabled: Bool) {
        notificationsDenied = false
        if enabled {
            MinecraftWatcher.shared.start { [weak self] in
                self?.notificationsDenied = true
            }
        } else {
            MinecraftWatcher.shared.stop()
        }
    }
}
