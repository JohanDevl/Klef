import IOKit.hid

/// Stable value-type identity for a physical keyboard.
///
/// `deviceID` is derived from `(vendorID, productID, locationID)` per PRD §7.
/// Two keyboards of the same model on different USB ports will have different
/// `locationID`s and therefore different `deviceID`s.
///
/// Equality and hashing are intentionally based on `deviceID` only — not on
/// the human-readable strings, which can drift between IOKit reads (e.g.
/// transport "USB" vs "USB ", productName casing). Without this, the
/// dominant-device short-circuit in `DominantDeviceTracker` would flip
/// spuriously when string fields fluctuate.
struct KeyboardDevice: Hashable, CustomStringConvertible {
    let vendorID: Int
    let productID: Int
    /// Best-effort; 0 when the IOKit property is absent (PRD §7).
    let locationID: Int
    let transport: String
    let productName: String
    let manufacturer: String

    /// Stable string identifier used as the key in `StaticMapping`.
    var deviceID: String {
        "v\(vendorID)-p\(productID)-loc\(locationID)"
    }

    var description: String {
        let label = productName.isEmpty ? "<unknown>" : productName
        return "\(label) [\(deviceID), \(transport)]"
    }

    static func == (lhs: KeyboardDevice, rhs: KeyboardDevice) -> Bool {
        lhs.deviceID == rhs.deviceID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(deviceID)
    }

    /// Builds a `KeyboardDevice` from a live `IOHIDDevice`.
    ///
    /// Returns `nil` only if the device exposes no usable identity at all
    /// (no vendor/product/location). Apple Silicon built-in keyboards travel
    /// over SPI and do NOT expose `kIOHIDVendorIDKey`/`kIOHIDProductIDKey` —
    /// they're only identifiable by `locationID` + product name. We default
    /// missing vendor/product to 0 so those devices are still tracked; the
    /// resulting `deviceID` (e.g. `v0-p0-loc282`) is stable on a given Mac.
    ///
    /// String properties from USB descriptors are attacker-controllable
    /// (CWE-117); they are sanitized at construction time so every consumer
    /// sees safe values.
    static func from(_ device: IOHIDDevice) -> KeyboardDevice? {
        func intProp(_ key: String) -> Int? {
            IOHIDDeviceGetProperty(device, key as CFString)
                .flatMap { $0 as? Int }
        }
        func strProp(_ key: String) -> String {
            (IOHIDDeviceGetProperty(device, key as CFString) as? String) ?? ""
        }

        let vendor = intProp(kIOHIDVendorIDKey) ?? 0
        let product = intProp(kIOHIDProductIDKey) ?? 0
        let location = intProp(kIOHIDLocationIDKey) ?? 0

        // Reject only if every numeric identifier is missing — without any of
        // them we cannot form a stable, distinguishable deviceID.
        guard vendor != 0 || product != 0 || location != 0 else { return nil }

        return KeyboardDevice(
            vendorID: vendor,
            productID: product,
            locationID: location,
            transport: sanitize(strProp(kIOHIDTransportKey)),
            productName: sanitize(strProp(kIOHIDProductKey)),
            manufacturer: sanitize(strProp(kIOHIDManufacturerKey))
        )
    }

    /// Strips ASCII control characters and Unicode default-ignorable code
    /// points, then truncates. Defends against ANSI-escape injection and log
    /// forgery via crafted USB descriptor strings.
    private static func sanitize(_ s: String, max: Int = 64) -> String {
        var out = String()
        out.reserveCapacity(min(s.count, max))
        for scalar in s.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F { continue }
            if scalar.properties.isDefaultIgnorableCodePoint { continue }
            out.unicodeScalars.append(scalar)
            if out.count >= max { break }
        }
        return out
    }
}
