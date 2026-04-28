/// Resolves a keyboard's `deviceID` to a Carbon TIS Input Source ID.
///
/// V0.1 ships a single conformer (`StaticMapping`) with hardcoded entries.
/// V0.3 will add a `UserDefaultsMapping` (FR-4) — depending on the protocol
/// here keeps that change isolated to a new file.
protocol DeviceLayoutMapping {
    func inputSource(for deviceID: String) -> String?
}

/// In-source `[DeviceID: InputSourceID]` mapping. Edit the entries in
/// `main.swift` after running klef once to discover your `deviceID`s.
struct StaticMapping: DeviceLayoutMapping {
    let entries: [String: String]

    func inputSource(for deviceID: String) -> String? {
        entries[deviceID]
    }
}
