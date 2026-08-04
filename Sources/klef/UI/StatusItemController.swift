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

    /// Re-reads `AppState` and picks the matching icon.
    ///
    /// Load-bearing rather than cosmetic: without Input Monitoring, Klef does
    /// nothing at all. macOS keys that grant to the binary's CDHash, which
    /// changes on every ad-hoc signed release — so *installing an update
    /// silently revokes it*. An unchanged icon would leave the user with an app
    /// that looks healthy and has quietly stopped working.
    ///
    /// Called on launch, after every HID start attempt, and whenever the menu
    /// opens.
    func refreshIcon() {
        setIcon(appState.permissionStatus == .granted ? .normal : .warning)
    }

    /// Swaps the menu-bar icon.
    ///
    /// Every branch resolves through a fallback chain and, if even that yields
    /// nothing, falls back to a text title. A nil image leaves the status item
    /// blank *and unclickable* — losing the user's only route to the menu. That
    /// matters most in `.warning`, which is exactly the state where they need
    /// to reach Settings.
    func setIcon(_ variant: IconVariant) {
        let image: NSImage?
        let toolTip: String
        let fallbackTitle: String

        switch variant {
        case .normal:
            image = MenuBarIcon.makeTemplate() ?? symbolImage("keyboard")
            toolTip = "Klef"
            fallbackTitle = "Klef"
        case .warning:
            // `keyboard.badge.exclamationmark` is NOT a real SF Symbol — it
            // returns nil. Verified, not assumed. `exclamationmark.triangle.fill`
            // is the reliable alert glyph; the brand glyph backs it up so the
            // item stays clickable no matter what.
            image = symbolImage("exclamationmark.triangle.fill")
                ?? MenuBarIcon.makeTemplate()
                ?? symbolImage("keyboard")
            toolTip = "Klef — Input Monitoring required"
            fallbackTitle = "Klef !"
        }

        statusItem.button?.image = image
        statusItem.button?.title = image == nil ? fallbackTitle : ""
        statusItem.button?.toolTip = toolTip
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        appState.refreshPermission()
        refreshIcon()
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
        refreshIcon()
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        // Banners come first: both describe a state in which the keyboard list
        // below them is either meaningless (no permission) or about to be
        // invalidated (pending update).
        if appState.permissionStatus != .granted {
            for item in permissionBannerItems() {
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }

        if let update = appState.availableUpdate {
            for item in updateBannerItems(for: update) {
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }

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

        let updateItem = NSMenuItem(
            title: appState.isCheckingForUpdate ? "Checking\u{2026}" : "Check for Updates\u{2026}",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.isEnabled = !appState.isCheckingForUpdate
        menu.addItem(updateItem)

        let quitItem = NSMenuItem(
            title: "Quit Klef",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Banner items

    /// Two items rather than one: a disabled headline that states the problem,
    /// and an actionable row that fixes it. Matches how the system's own status
    /// menus present a degraded state.
    private func permissionBannerItems() -> [NSMenuItem] {
        let headline = NSMenuItem(
            title: "Not monitoring \u{2014} permission required",
            action: nil,
            keyEquivalent: ""
        )
        headline.isEnabled = false
        headline.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )

        let action = NSMenuItem(
            title: "Grant Input Monitoring\u{2026}",
            action: #selector(openInputMonitoringSettings),
            keyEquivalent: ""
        )
        action.target = self

        return [headline, action]
    }

    private func updateBannerItems(for update: AvailableUpdate) -> [NSMenuItem] {
        let headline = NSMenuItem(
            title: "Klef \(update.version) is available",
            action: nil,
            keyEquivalent: ""
        )
        headline.isEnabled = false
        headline.image = NSImage(
            systemSymbolName: "arrow.down.circle.fill",
            accessibilityDescription: nil
        )

        let action = NSMenuItem(
            title: "Open Download Page\u{2026}",
            action: #selector(openReleasePage),
            keyEquivalent: ""
        )
        action.target = self

        // Stated here, not only in the release notes: after installing, the
        // rebuilt binary has a new CDHash and macOS drops the Input Monitoring
        // grant. A user who isn't told hits a silently dead app and blames Klef.
        let caveat = NSMenuItem(
            title: "You'll need to re-grant Input Monitoring after installing.",
            action: nil,
            keyEquivalent: ""
        )
        caveat.isEnabled = false

        return [headline, action, caveat]
    }

    // MARK: - Actions

    @objc private func openInputMonitoringSettings() {
        InputMonitoring.openSystemSettingsDeeplink()
    }

    @objc private func openReleasePage() {
        guard let update = appState.availableUpdate else { return }
        NSWorkspace.shared.open(update.releaseURL)
    }

    @objc private func checkForUpdates() {
        appState.checkForUpdates(explicit: true)
    }

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
