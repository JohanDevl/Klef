import SwiftUI

/// One row in the Settings keyboard list.
///
/// All mutations are routed through closures; this view never touches AppState
/// directly. The parent (`SettingsView`) wires closures to AppState methods.
struct KeyboardRowView: View {

    let entry: DeviceMappingEntry
    let isConnected: Bool
    let availableSources: [InputSourceInfo]
    let onSelectSource: (String?) -> Void
    let onToggleIgnore: (Bool) -> Void

    // MARK: - Derived

    /// SF Symbol name keyed off the IOKit transport string. IOKit returns
    /// free-form values (`"USB"`, `"Bluetooth"`, `"Bluetooth Low Energy"`,
    /// `"SPI"`, `"Apple"`), so a substring match beats an enum here.
    private var transportSymbol: String {
        let t = entry.lastSeenTransport.lowercased()
        if t.contains("bluetooth") || t.contains("bt") { return "wave.3.right" }
        if t.contains("usb") { return "cable.connector" }
        return "keyboard"
    }

    /// Short identifier badge parsed from deviceID (`v<vID>-p<pID>-loc<locID>`).
    /// `locationID` is dropped from the badge to keep the row narrow.
    private var deviceBadge: String {
        let parts = entry.deviceID.split(separator: "-")
        let vPart = parts.first(where: { $0.hasPrefix("v") }) ?? Substring(entry.deviceID)
        let pPart = parts.first(where: { $0.hasPrefix("p") }) ?? ""
        return pPart.isEmpty ? String(vPart) : "\(vPart)-\(pPart)"
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            // Connectivity dot
            Circle()
                .fill(isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .help(entry.lastSeenTransport.isEmpty ? "Unknown transport" : entry.lastSeenTransport)

            // Transport icon
            Image(systemName: transportSymbol)
                .frame(width: 18)

            // Name + ID badge
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayLabel)
                    .fontWeight(.medium)
                Text(deviceBadge)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Input-source picker
            Picker("", selection: Binding<String?>(
                get: { entry.inputSourceID },
                set: { onSelectSource($0) }
            )) {
                Text("(none)").tag(String?.none)
                ForEach(availableSources, id: \.id) { source in
                    Text(source.localizedName).tag(Optional(source.id))
                }
            }
            .labelsHidden()
            .frame(minWidth: 160)
            .disabled(entry.ignored)

            // Active toggle — "Active = on" maps to "ignored = false". The
            // model still stores `ignored` (an explicit opt-out for misclassified
            // peripherals); the UI shows the friendlier inverse so the default
            // ON state reads as "Klef is switching for this keyboard."
            Toggle("Active", isOn: Binding<Bool>(
                get: { !entry.ignored },
                set: { onToggleIgnore(!$0) }
            ))
            .toggleStyle(.switch)
            .help("Turn off to stop Klef from switching for this keyboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .opacity(isConnected ? 1.0 : 0.6)
    }
}
