# Minecraft Helper

A small native Mac app you launch when you want to play Minecraft. It has a
switch for each override so every piece can be tested independently:

| Override | What it does | How |
| --- | --- | --- |
| **Ctrl + Click stays a left click** | Ctrl-clicking no longer counts as a right-click | A CGEventTap strips the Control flag from left-mouse events (same approach as [DisableCtrlClick](https://github.com/achendev/DisableCtrlClick)) |
| **F1–F12 act as standard function keys** | F3 = debug screen instead of Mission Control, etc., without holding Fn | Flips the system fn-key mode live via IOHIDSystem (same mechanism as Fluor); restored when toggled off or on quit |
| **Shift + Scroll scrolls normally** | Shift-scrolling no longer becomes horizontal/reversed scrolling | The event tap strips the Shift flag from scroll-wheel events (same trick as LinearMouse's scrolling modifiers) |
| **Pointer acceleration off** | Mouse movement is 1:1 for consistent aim | Sets the session-wide IOHIDSystem acceleration parameters and the per-device `HIDUseLinearScalingMouseAcceleration` / acceleration properties (the LinearMouse mechanism); previous values are snapshotted and restored |
| **Shake-to-locate cursor off** | Fast mouse flicks no longer balloon the cursor | Writes `CGDisableCursorLocationMagnification` in `com.apple.universalaccess` — the key behind Accessibility → Display → "Shake mouse pointer to locate". Needs **Full Disk Access** (macOS protects that domain); previous value restored on disable/quit |
| **Remind me to quit** | Notification when you've stopped playing | Polls `pgrep` every 5 s for a Java process whose command line mentions Minecraft; after 60 s of absence posts a notification with Quit/Cancel. After Cancel it stays quiet until Minecraft is seen running again |

Keyboard events are never modified, so holding Ctrl (sprint) and Shift (sneak)
still work — only the modifier flags carried on *mouse* events are touched.

## Build & run

```sh
./Scripts/build-app.sh
open "build/Minecraft Helper.app"
```

Permissions, per override:

- **Ctrl-click / Shift-scroll** — need **Accessibility** access (System
  Settings → Privacy & Security → Accessibility). The app prompts the first
  time you enable one, and the override kicks in the moment access is granted.
- **Shake-to-locate** — needs **Full Disk Access**; the app shows a banner
  with a shortcut button when it can't write the setting. On some macOS
  versions the change may only fully apply after the next login.
- **Remind me to quit** — asks for **Notifications** permission when enabled.
- **Function keys / pointer acceleration** — no permission needed.

> **Note:** the app is ad-hoc signed, so after every rebuild macOS treats it
> as a new app — remove and re-add it in the Accessibility list (or toggle
> its entry off/on) after rebuilding.

## Behavior notes

- Overrides are global while enabled — quit the app (or flip the switches
  off) when you're done playing.
- Closing the window keeps the app (and overrides) running; use the Dock
  icon to reopen it, quit with ⌘Q.
- Switch states persist across launches; the fn-key mode you had before
  enabling that override is restored on disable/quit.
