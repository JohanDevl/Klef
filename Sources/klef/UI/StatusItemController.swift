import AppKit

/// Owns the `NSStatusItem`, builds the menu, and routes actions.
///
/// Inherits from `NSObject` so `@objc` selectors work with `target: self`.
/// Also conforms to `NSMenuDelegate`: the keyboard list is rebuilt from the
/// current `AppState` snapshot every time the user opens the menu (same model
/// as the system Bluetooth / Wi-Fi menus). This avoids any Combine plumbing to
/// keep the menu in lockstep with `@Published` mutations.
final class StatusItemController: NSObject, NSMenuDelegate {

    // MARK: - Types

    enum IconVariant {
        case normal
        case warning
    }

    // MARK: - Private state

    private let statusItem: NSStatusItem
    private let appState: AppState
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    // MARK: - Init

    init(
        appState: AppState,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.appState = appState
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
    }

    // MARK: - Public API

    /// Swaps the menu-bar icon.
    ///
    /// V0.3 only calls `.normal`. The `.warning` variant is wired now so V1.0
    /// FR-6 can surface the permission-denied state without touching this class.
    func setIcon(_ variant: IconVariant) {
        let image: NSImage?
        let toolTip: String

        switch variant {
        case .normal:
            // Brand glyph, with the SF Symbol as a fallback so a parse failure
            // can't leave the status item blank and unclickable.
            image = MenuBarIcon.makeTemplate() ?? symbolImage("keyboard")
            toolTip = "Klef"
        case .warning:
            // Stays an SF Symbol: the brand glyph has no badged variant, and the
            // system symbol carries the alert semantics for free.
            // SF Symbols 4 (macOS 13+). No earlier fallback needed since
            // LSMinimumSystemVersion is 13.0.
            image = symbolImage("keyboard.badge.exclamationmark")
            toolTip = "Klef — Input Monitoring required"
        }

        statusItem.button?.image = image
        statusItem.button?.toolTip = toolTip
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    // MARK: - Private helpers

    private func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Klef")
        image?.isTemplate = true
        return image
    }

    private func configure() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
        setIcon(.normal)
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let keyboardItems = KeyboardMenuBuilder.keyboardSectionItems(
            state: appState,
            target: self,
            selectInputSourceAction: #selector(handleSelectInputSource(_:)),
            toggleIgnoredAction: #selector(handleToggleIgnored(_:))
        )
        for item in keyboardItems {
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Open Klef Settings\u{2026}",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit Klef",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quitApp() {
        onQuit()
    }

    @objc private func handleSelectInputSource(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? KeyboardMenuPayload else { return }
        appState.setInputSource(
            deviceID: payload.deviceID,
            inputSourceID: payload.inputSourceID
        )
    }

    @objc private func handleToggleIgnored(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? KeyboardMenuPayload else { return }
        let current = appState.devices[payload.deviceID]?.ignored ?? false
        appState.setIgnored(deviceID: payload.deviceID, ignored: !current)
    }
}
