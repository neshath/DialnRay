import AppKit
import DialnRayCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: SettingsStore, permissions: PermissionManager, license: LicenseService, onTestOverlay: @escaping () -> Void) {
        let root = SettingsRootView(
            settings: settings,
            permissions: permissions,
            license: license,
            onTestOverlay: onTestOverlay
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "DialnRay Settings"
        window.setContentSize(NSSize(width: 680, height: 540))
        window.minSize = NSSize(width: 620, height: 500)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsRootView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var license: LicenseService
    let onTestOverlay: () -> Void

    var body: some View {
        TabView {
            behavior
                .tabItem { Label("Behavior", systemImage: "scope") }
            scanning
                .tabItem { Label("Scanning", systemImage: "viewfinder") }
            appearance
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            permissionsView
                .tabItem { Label("Permissions", systemImage: "hand.raised") }
            licenseView
                .tabItem { Label("License", systemImage: "key") }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 500)
        .onAppear {
            permissions.refresh()
            permissions.monitorPermissionChanges()
        }
    }

    private var behavior: some View {
        Form {
            Section("Activation") {
                Picker("Activation mode", selection: $settings.activationMode) {
                    ForEach(ActivationMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.activationMode != .explicit {
                    ValueSlider(
                        title: "Dwell time",
                        value: $settings.dwellDuration,
                        range: 0.3...2.5,
                        step: 0.1,
                        valueText: String(format: "%.1f seconds", settings.dwellDuration),
                        help: "How long a direction must remain stable before DialnRay latches."
                    )
                }
                if settings.activationMode == .dwellAutoClick {
                    Text("After activation, DialnRay stays open. Return to the center before choosing another target.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Option–Space opens DialnRay. Escape always cancels. Return confirms the current target.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Test DialnRay") { onTestOverlay() }
                        .buttonStyle(.borderedProminent)
                    Text("Opens the dial at your pointer without relying on the shortcut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Movement accommodation") {
                ValueSlider(
                    title: "Jitter tolerance",
                    value: $settings.jitterTolerance,
                    range: 4...48,
                    step: 1,
                    valueText: "\(Int(settings.jitterTolerance)) points",
                    help: "Pointer movement inside this radius keeps the current dwell active."
                )
                ValueSlider(
                    title: "Motion smoothing",
                    value: $settings.smoothing,
                    range: 0...0.92,
                    step: 0.02,
                    valueText: "\(Int(settings.smoothing * 100))%",
                    help: "Higher values reduce tremor but respond more slowly."
                )
            }
        }
        .formStyle(.grouped)
    }

    private var scanning: some View {
        Form {
            Section("Adaptive recognition") {
                Toggle("Use visual recognition when Accessibility is incomplete", isOn: $settings.visionFallback)
                Text("DialnRay first reads the frontmost app's Accessibility hierarchy. With permission, it can inspect the active window locally using Vision when custom controls are not exposed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Screenshots and recognized text never leave this Mac.")
                    .font(.callout.weight(.medium))
            }

            Section("Search area") {
                ValueSlider(
                    title: "Target radius",
                    value: $settings.targetRadius,
                    range: 300...1400,
                    step: 20,
                    valueText: "\(Int(settings.targetRadius)) points",
                    help: "Controls beyond this distance are omitted from the focus field."
                )
                Stepper("Maximum visible targets: \(settings.maximumTargets)", value: $settings.maximumTargets, in: 3...12)
                Text("App-specific scan profiles are learned locally from which sources successfully find usable targets.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Section("Focus field") {
                Toggle("Show compact diagnostics rail", isOn: $settings.diagnosticsVisible)
                ValueSlider(
                    title: "Ray intensity",
                    value: $settings.rayIntensity,
                    range: 0.25...1,
                    step: 0.05,
                    valueText: "\(Int(settings.rayIntensity * 100))%",
                    help: "Changes nonselected ray visibility without weakening the selected target."
                )
            }
            Section("System accessibility") {
                systemSettingRow("Reduce Motion", enabled: settings.reduceMotion)
                systemSettingRow("Reduce Transparency", enabled: settings.reduceTransparency)
                systemSettingRow("Increase Contrast", enabled: settings.increaseContrast)
                Text("DialnRay follows these macOS display settings automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var permissionsView: some View {
        Form {
            Section("Accessibility") {
                permissionRow(
                    title: "Control other apps",
                    detail: "Required to inspect controls, observe the shortcut, and activate the selected target.",
                    granted: permissions.accessibilityTrusted,
                    actionTitle: "Request Access",
                    action: permissions.requestAccessibility
                )
                if !permissions.accessibilityTrusted {
                    Text("If DialnRay is missing from the list, reveal this exact app, click + in System Settings, select DialnRay.app, then switch it on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Open Accessibility Settings") { permissions.openAccessibilitySettings() }
                        Button("Reveal DialnRay in Finder") { permissions.revealApplication() }
                    }
                }
            }
            Section("Screen Recording") {
                permissionRow(
                    title: "Recognize custom interfaces",
                    detail: "Optional. Used only when an app does not expose enough controls through Accessibility.",
                    granted: permissions.screenRecordingGranted,
                    actionTitle: "Request Screen Recording",
                    action: permissions.requestScreenRecording
                )
            }
            HStack {
                Button("Refresh permission status") { permissions.refresh() }
                Button("Test DialnRay") { onTestOverlay() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!permissions.accessibilityTrusted)
            }
        }
        .formStyle(.grouped)
    }

    private var licenseView: some View {
        Form {
            Section("DialnRay annual license") {
                HStack(spacing: 10) {
                    Image(systemName: licenseSymbol)
                        .foregroundStyle(licenseColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(licenseTitle).font(.headline)
                        Text(licenseDetail).font(.callout).foregroundStyle(.secondary)
                    }
                }

                TextField("Gumroad license key", text: $license.enteredKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Gumroad license key")
                HStack {
                    Button("Activate license") { Task { await license.activate() } }
                        .disabled(license.enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Verify now") { Task { await license.refreshIfNeeded(force: true) } }
                    Spacer()
                    Button("Remove from this Mac", role: .destructive) { license.deactivate() }
                }
                Text("Routine checks do not increase Gumroad's license-use count. After a successful check, DialnRay allows seven days of offline use.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func permissionRow(title: String, detail: String, granted: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button(actionTitle, action: action) }
        }
    }

    private func systemSettingRow(_ title: String, enabled: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(enabled ? "On" : "Off")
                .foregroundStyle(enabled ? Color.green : Color.secondary)
        }
    }

    private var licenseTitle: String {
        switch license.status {
        case .configurationRequired: return "Gumroad product ID required"
        case .missing: return "License not activated"
        case .checking: return "Checking license…"
        case .valid: return "License active"
        case .invalid: return "License needs attention"
        }
    }

    private var licenseDetail: String {
        switch license.status {
        case .configurationRequired: return "Add the product ID from Gumroad's license-key block before distributing the app."
        case .missing: return "Paste the key included with your Gumroad purchase."
        case .checking: return "Contacting Gumroad securely."
        case .valid(let email, let offline):
            let identity = email ?? "Verified purchase"
            return offline ? "\(identity) · offline grace period" : identity
        case .invalid(let reason): return reason
        }
    }

    private var licenseSymbol: String {
        switch license.status {
        case .valid: return "checkmark.seal.fill"
        case .checking: return "clock"
        case .invalid: return "xmark.octagon.fill"
        default: return "key"
        }
    }

    private var licenseColor: Color {
        switch license.status {
        case .valid: return .green
        case .invalid: return .red
        case .checking: return .cyan
        default: return .secondary
        }
    }
}

private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
