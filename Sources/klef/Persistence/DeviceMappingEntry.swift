import Foundation

/// One persisted mapping entry for a physical keyboard.
///
/// Conforms to `Codable` for UserDefaults persistence via `MappingsStore`.
/// `id` (= `deviceID`) is the stable `v<vID>-p<pID>-loc<locID>` key, matching
/// `KeyboardDevice.deviceID`, so the two can be correlated without importing
/// the HID layer into the Persistence layer.
struct DeviceMappingEntry: Codable, Identifiable, Equatable {

    // MARK: - Identity

    /// Stable device key, format `v<vendorID>-p<productID>-loc<locationID>`.
    let deviceID: String

    var id: String { deviceID }

    // MARK: - Mapping

    /// The TIS input-source identifier the user has assigned.
    /// `nil` means "not yet mapped" (shown as "(none)" in the UI).
    var inputSourceID: String?

    /// When `true`, the engine skips this keyboard and never switches sources.
    var ignored: Bool

    // MARK: - Display

    /// Optional user-supplied rename; takes precedence over `lastSeenProductName`.
    var displayName: String?

    // MARK: - Last-seen snapshot (for disconnected-row display)

    /// Product name captured at last plug-in event; preserved so disconnected
    /// rows still display a human-readable name.
    var lastSeenProductName: String

    /// Transport string (`USB`, `Bluetooth`, `SPI`, …) for icon selection.
    var lastSeenTransport: String

    /// Timestamp of last plug-in event; useful for sort order and diagnostics.
    var lastSeenAt: Date

    // MARK: - Computed

    /// The label shown in UI rows.
    ///
    /// Priority: user-set `displayName` > `lastSeenProductName` > `"<unknown>"`.
    var displayLabel: String {
        if let name = displayName, !name.isEmpty { return name }
        if !lastSeenProductName.isEmpty { return lastSeenProductName }
        return "<unknown>"
    }
}
