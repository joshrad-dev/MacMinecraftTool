# Minecraft Helper

A small native Mac app you launch when you want to play Minecraft. It has a
switch for each override so every piece can be tested independently:

| Override | What it does | How |
| --- | --- | --- |
| **Ctrl + Click stays a left click** | Ctrl-clicking no longer counts as a right-click | A CGEventTap strips the Control flag from left-mouse events (same approach as [DisableCtrlClick](https://github.com/achendev/DisableCtrlClick)) |
| **Ctrl + Q drops a whole stack** | Ctrl+Q throws the full stack instead of one item, with no client mods | On macOS the game's "control held" check reads the Command keys, and ⌘Q is the Quit shortcut. While Minecraft is frontmost, the event tap wraps Ctrl+Q in a synthetic Command press/release, so the game sees Command held but the Q event never carries the Command flag that would trigger Quit |
| **F1–F12 act as standard function keys** | F3 = debug screen instead of Mission Control, etc., without holding Fn | Flips the system fn-key mode live via IOHIDSystem (same mechanism as Fluor); restored when toggled off or on quit |
| **Shift + Scroll scrolls normally** | Shift-scrolling no longer becomes horizontal/reversed scrolling | The event tap strips the Shift flag from scroll-wheel events (same trick as LinearMouse's scrolling modifiers) |
| **Pointer acceleration off** | Mouse movement is 1:1 for consistent aim | Sets the session-wide IOHIDSystem acceleration parameters and the per-device `HIDUseLinearScalingMouseAcceleration` / acceleration properties (the LinearMouse mechanism); previous values are snapshotted and restored |
| **Remind me to quit** | Notification when you've stopped playing | Polls `pgrep` every 5 s for a Java process whose command line mentions Minecraft; after 60 s of absence posts a notification with Quit/Cancel. After Cancel it stays quiet until Minecraft is seen running again |

The only keyboard events touched are Ctrl+Q while Minecraft is frontmost, so
holding Ctrl (sprint) and Shift (sneak) still work — otherwise only the
modifier flags carried on *mouse* events are changed.

## Build & run

```sh
./Scripts/build-app.sh
open "build/Minecraft Helper.app"
```

The app icon's editable artwork is `Resources/AppIcon.svg`. Its native
Icon Composer document is `Resources/AppIcon.icon`, with an ivory default
background and a system-dark background. Builds require Xcode 26 or later;
`actool` packages the appearance variants in `Assets.car` and generates an
`.icns` fallback for older macOS versions. No runtime icon switching is needed.
On macOS 26 or later, the icon follows the user's icon appearance selection.

After editing the SVG, run `python3 Scripts/prepare-icon.py` to update the
Icon Composer artwork, then rebuild. Open `Resources/AppIcon.icon` in Icon
Composer to edit its appearance settings. `bash Scripts/build-icon.sh`
also regenerates a standalone legacy icon and PNG preview (requires
`brew install librsvg`).

Permissions, per override:

- **Ctrl-click / Shift-scroll / Ctrl+Q** — need **Accessibility** access (System
  Settings → Privacy & Security → Accessibility). The app prompts the first
  time you enable one, and the override kicks in the moment access is granted.
- **Remind me to quit** — asks for **Notifications** permission when enabled.
- **Function keys / pointer acceleration** — no permission needed.

Accessibility is the only elevated permission the app asks for. Anything
needing Full Disk Access is deliberately out of scope.

> **Note:** the app is ad-hoc signed, so after every rebuild macOS treats it
> as a new app — remove and re-add it in the Accessibility list (or toggle
> its entry off/on) after rebuilding.

## Behavior notes

- Overrides are global while enabled — quit the app (or flip the switches
  off) when you're done playing.
- The fn-key mode and pointer acceleration are system-wide settings that
  outlive the process, so the app puts both back when it quits. It also
  records which ones are applied, so if it's ever force-quit or crashes, the
  next launch restores them before doing anything else.
- Closing the window keeps the app (and overrides) running; use the Dock
  icon to reopen it, quit with ⌘Q.
- Switch states persist across launches; the fn-key mode you had before
  enabling that override is restored on disable/quit.
