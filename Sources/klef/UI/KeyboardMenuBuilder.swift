import AppKit

/// Payload attached to `NSMenuItem.representedObject` so the controller's
/// `@objc` actions can recover which keyboard / input source the click targets.
///
/// `NSObject` subclass because `representedObject` is `Any?` bridged from
/// Objective-C — Swift structs cross that bridge as opaque boxes that can't be
/// downcast cleanly.
final class KeyboardMenuPayload: NSObject {
    let deviceID: String
    let inputSourceID: String?

    init(deviceID: String, inputSourceID: String?) {
        self.deviceID = deviceID
        self.inputSourceID = inputSourceID
        super.init()
    }
}

/// Pure translation `AppState → [NSMenuItem]` for the status-bar menu.
///
/// Stateless on purpose: the controller calls this on every `menuNeedsUpdate`
/// and rebuilds from the latest `AppState` snapshot.
enum KeyboardMenuBuilder {

    /// Returns the items to insert above the static `Settings… / Quit` block.
    /// Always returns at least one item: either a row per connected keyboard,
    /// or a single disabled "No keyboards detected" placeholder.
    static func keyboardSectionItems(
        state: AppState,
        target: AnyObject,
        selectInputSourceAction: Selector,
        toggleIgnoredAction: Selector
    ) -> [NSMenuItem] {
        let connected = state.partitionedDevices.connected

        if connected.isEmpty {
            let empty = NSMenuItem()
            empty.title = "No keyboards detected"
            empty.isEnabled = false
            return [empty]
        }

        return connected.map { entry in
            makeKeyboardItem(
                entry: entry,
                sources: state.availableInputSources,
                target: target,
                selectInputSourceAction: selectInputSourceAction,
                toggleIgnoredAction: toggleIgnoredAction
            )
        }
    }

    // MARK: - Private builders

    private static func makeKeyboardItem(
        entry: DeviceMappingEntry,
        sources: [InputSourceInfo],
        target: AnyObject,
        selectInputSourceAction: Selector,
        toggleIgnoredAction: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = entry.displayLabel
        item.image = transportImage(for: entry.lastSeenTransport)
        item.submenu = makeSubmenu(
            entry: entry,
            sources: sources,
            target: target,
            selectInputSourceAction: selectInputSourceAction,
            toggleIgnoredAction: toggleIgnoredAction
        )
        return item
    }

    private static func makeSubmenu(
        entry: DeviceMappingEntry,
        sources: [InputSourceInfo],
        target: AnyObject,
        selectInputSourceAction: Selector,
        toggleIgnoredAction: Selector
    ) -> NSMenu {
        let submenu = NSMenu()

        let header = NSMenuItem()
        header.title = "Set layout"
        header.isEnabled = false
        submenu.addItem(header)
        submenu.addItem(NSMenuItem.separator())

        if sources.isEmpty {
            let none = NSMenuItem()
            none.title = "(no input sources available)"
            none.isEnabled = false
            submenu.addItem(none)
        } else {
            submenu.addItem(makeSourceItem(
                title: "(none)",
                inputSourceID: nil,
                entry: entry,
                target: target,
                action: selectInputSourceAction
            ))

            for source in sources {
                submenu.addItem(makeSourceItem(
                    title: source.localizedName,
                    inputSourceID: source.id,
                    entry: entry,
                    target: target,
                    action: selectInputSourceAction
                ))
            }
        }

        submenu.addItem(NSMenuItem.separator())

        let toggle = NSMenuItem(
            title: "Auto-switch on this keyboard",
            action: toggleIgnoredAction,
            keyEquivalent: ""
        )
        toggle.target = target
        toggle.representedObject = KeyboardMenuPayload(
            deviceID: entry.deviceID,
            inputSourceID: nil
        )
        toggle.state = entry.ignored ? .off : .on
        submenu.addItem(toggle)

        return submenu
    }

    private static func makeSourceItem(
        title: String,
        inputSourceID: String?,
        entry: DeviceMappingEntry,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = KeyboardMenuPayload(
            deviceID: entry.deviceID,
            inputSourceID: inputSourceID
        )
        item.state = (entry.inputSourceID == inputSourceID) ? .on : .off
        // Greying out source picks while ignored mirrors the SwiftUI Picker's
        // `.disabled(entry.ignored)` in KeyboardRowView so both UIs read the
        // same way: "Auto-switch off → mapping is dormant."
        item.isEnabled = !entry.ignored
        return item
    }

    /// Mirrors `KeyboardRowView.transportSymbol`: substring match because
    /// IOKit returns free-form transport strings (`USB`, `Bluetooth`,
    /// `Bluetooth Low Energy`, `SPI`, `Apple`, …).
    private static func transportImage(for transport: String) -> NSImage? {
        let t = transport.lowercased()
        let symbol: String
        if t.contains("bluetooth") || t.contains("bt") {
            symbol = "wave.3.right"
        } else if t.contains("usb") {
            symbol = "cable.connector"
        } else {
            symbol = "keyboard"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }
}
