import AppKit

/// Owns the `NSStatusItem`, builds the menu, and routes actions.
///
/// Inherits from `NSObject` so `@objc` selectors work with `target: self`.
final class StatusItemController: NSObject {

    // MARK: - Types

    enum IconVariant {
        case normal
        case warning
    }

    // MARK: - Private state

    private let statusItem: NSStatusItem
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    // MARK: - Init

    init(onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
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
        let symbolName: String
        let toolTip: String

        switch variant {
        case .normal:
            symbolName = "keyboard"
            toolTip = "Klef"
        case .warning:
            // SF Symbols 4 (macOS 13+). No earlier fallback needed since
            // LSMinimumSystemVersion is 13.0.
            symbolName = "keyboard.badge.exclamationmark"
            toolTip = "Klef — Input Monitoring required"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Klef")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = toolTip
    }

    // MARK: - Private helpers

    private func configure() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Open Klef Settings\u{2026}",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Klef",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        setIcon(.normal)
    }

    // MARK: - Actions

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quitApp() {
        onQuit()
    }
}
