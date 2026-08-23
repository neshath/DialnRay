import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onActivate: (() -> Void)?
    var onSettings: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let activateItem = NSMenuItem(title: "Open DialnRay", action: #selector(activate), keyEquivalent: " ")
    private let permissionItem = NSMenuItem(title: "Permissions", action: #selector(settings), keyEquivalent: "")

    override init() {
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "scope", accessibilityDescription: "DialnRay")
            button.toolTip = "DialnRay"
        }
        activateItem.keyEquivalentModifierMask = [.option]
        activateItem.target = self
        permissionItem.target = self
        menu.addItem(activateItem)
        menu.addItem(.separator())
        menu.addItem(permissionItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit DialnRay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        activateItem.title = "Open DialnRay"
    }

    @objc private func activate() { onActivate?() }
    @objc private func settings() { onSettings?() }
}
