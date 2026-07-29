import Foundation

/// Toggles "Shake mouse pointer to locate" (System Settings → Accessibility
/// → Display) by writing `CGDisableCursorLocationMagnification` in the
/// `com.apple.universalaccess` preference domain — the same key the settings
/// pane writes.
///
/// Reading the domain is always allowed, but *writing* it is TCC-protected:
/// it silently fails unless the app has Full Disk Access. `setShakeDisabled`
/// reports that failure so the UI can point the user at the FDA settings.
enum ShakeToLocateManager {
    private static let key = "CGDisableCursorLocationMagnification" as CFString
    private static let domain = "com.apple.universalaccess" as CFString

    /// Tri-state saved value: the key may be absent entirely (system default,
    /// shake enabled) — restoring then means removing the key again.
    enum SavedValue: Int {
        case absent = -1
        case shakeEnabled = 0
        case shakeDisabled = 1
    }

    static func currentValue() -> SavedValue {
        guard let value = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
              let number = value as? NSNumber else {
            return .absent
        }
        return number.boolValue ? .shakeDisabled : .shakeEnabled
    }

    @discardableResult
    static func setShakeDisabled(_ disabled: Bool) -> Bool {
        CFPreferencesSetValue(key, disabled ? kCFBooleanTrue : kCFBooleanFalse,
                              domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    @discardableResult
    static func restore(_ saved: SavedValue) -> Bool {
        switch saved {
        case .absent:
            CFPreferencesSetValue(key, nil, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        case .shakeEnabled:
            return setShakeDisabled(false)
        case .shakeDisabled:
            return setShakeDisabled(true)
        }
    }
}
