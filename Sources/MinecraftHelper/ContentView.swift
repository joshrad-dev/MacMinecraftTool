import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: OverridesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacMinecraftTool")
                    .font(.title2.bold())
                Text("Flip these on when you're playing, off when you're done.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $model.masterSwitch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Master switch")
                            .font(.body.weight(.semibold))
                        Text("Turns on/off every checked override below at once. Unchecked overrides are left alone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 14) {
                overrideRow(
                    included: $model.ctrlClickIncluded,
                    isOn: $model.ctrlClickOverride,
                    title: "Ctrl + Click stays a left click",
                    caption: "Stops Ctrl-clicks from being treated as right-clicks, so you can sprint-mine without placing blocks."
                )
                Divider()
                overrideRow(
                    included: $model.dropStackIncluded,
                    isOn: $model.dropStackOverride,
                    title: "Ctrl + Q drops a whole stack",
                    caption: "Minecraft on Mac expects ⌘Q for this, which quits the game. While Minecraft is in front, Ctrl + Q is passed to the game as ⌘ + Q without triggering Quit."
                )
                Divider()
                overrideRow(
                    included: $model.functionKeysIncluded,
                    isOn: $model.functionKeysOverride,
                    title: "F1–F12 act as standard function keys",
                    caption: "F3 opens the debug screen instead of Mission Control. No need to hold Fn or change System Settings."
                )
                if let error = model.functionKeyError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Divider()
                overrideRow(
                    included: $model.shiftScrollIncluded,
                    isOn: $model.shiftScrollOverride,
                    title: "Shift + Scroll scrolls normally",
                    caption: "Stops macOS from turning Shift-scroll into horizontal/reversed scrolling, so the hotbar scrolls correctly while sneaking."
                )
                Divider()
                overrideRow(
                    included: $model.pointerAccelIncluded,
                    isOn: $model.pointerAccelOverride,
                    title: "Pointer acceleration off",
                    caption: "Makes mouse movement 1:1 so aiming feels consistent. Your previous speed settings come back when this is turned off."
                )
                if let error = model.pointerAccelError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Divider()
                overrideRow(
                    included: $model.quitReminderIncluded,
                    isOn: $model.quitReminderEnabled,
                    title: "Remind me to quit",
                    caption: "If no Minecraft (Java) process has been running for a minute, sends a notification offering to quit the app."
                )
                if model.notificationsDenied {
                    Label("Notifications are off for MacMinecraftTool — allow them in System Settings → Notifications.",
                          systemImage: "bell.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            if model.needsAccessibility {
                accessibilityBanner
            }
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize()
    }

    private func overrideRow(included: Binding<Bool>, isOn: Binding<Bool>, title: String, caption: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: included) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Include this override when the master switch is used")
                .padding(.top, 2)

            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private var accessibilityBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("The click, scroll, and Ctrl + Q overrides need Accessibility access. They'll start working the moment access is granted.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Accessibility Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
