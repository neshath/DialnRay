import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let permissions = PermissionManager()
    private let license = LicenseService()
    private var coordinator: AppCoordinator!
    private var menuBar: MenuBarController!
    private var settingsWindow: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator = AppCoordinator(settings: settings, permissions: permissions, license: license)
        settingsWindow = SettingsWindowController(
            settings: settings,
            permissions: permissions,
            license: license,
            onTestOverlay: { [weak self] in self?.coordinator.activateOverlay() }
        )
        menuBar = MenuBarController()
        menuBar.onActivate = { [weak self] in self?.coordinator.toggleOverlay() }
        menuBar.onSettings = { [weak self] in self?.settingsWindow.present() }
        coordinator.onNeedsSettings = { [weak self] in self?.settingsWindow.present() }
        coordinator.start()

        if ProcessInfo.processInfo.arguments.contains("--preview-overlay") {
            coordinator.previewOverlay()
            return
        }

        if !settings.firstLaunchComplete {
            settings.firstLaunchComplete = true
            settingsWindow.present()
            permissions.requestAccessibility()
        }

        if ProcessInfo.processInfo.arguments.contains("--activate-on-launch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.coordinator.activateOverlay()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
