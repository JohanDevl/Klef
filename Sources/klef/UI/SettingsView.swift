import SwiftUI

/// Root view for the Settings window.
///
/// Injected as an `@EnvironmentObject` so nested views can read `AppState`
/// without prop-drilling. All mutations go through `AppState` methods;
/// no direct `UserDefaults` access occurs here.
struct SettingsView: View {

    @EnvironmentObject var state: AppState

    var body: some View {
        let partition = state.partitionedDevices

        Form {
            // MARK: - Permission / HID-status header

            if state.permissionStatus != .granted {
                Section {
                    permissionBanner
                }
            } else if !state.hidIsRunning {
                Section {
                    hidStalledBanner
                }
            }

            // MARK: - General

            Section("General") {
                LaunchAtLoginToggleView()
                UpdateCheckView()
            }

            // MARK: - Connected keyboards

            Section("Connected") {
                if partition.connected.isEmpty {
                    Text("No keyboards detected.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(partition.connected) { entry in
                        row(for: entry, isConnected: true)
                    }
                }
            }

            // MARK: - Known but disconnected keyboards

            if !partition.disconnected.isEmpty {
                Section("Known, not connected") {
                    ForEach(partition.disconnected) { entry in
                        row(for: entry, isConnected: false)
                    }
                }
            }

            // MARK: - Switching note

            Section {
                Text("Switching takes effect on the next event from the keyboard.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // MARK: - About

            Section("About") {
                AboutView()
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 380)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func row(for entry: DeviceMappingEntry, isConnected: Bool) -> some View {
        KeyboardRowView(
            entry: entry,
            isConnected: isConnected,
            availableSources: state.availableInputSources,
            onSelectSource: { sourceID in
                state.setInputSource(deviceID: entry.deviceID, inputSourceID: sourceID)
            },
            onToggleIgnore: { ignored in
                state.setIgnored(deviceID: entry.deviceID, ignored: ignored)
            }
        )
        .listRowInsets(EdgeInsets())
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 4) {
                Text("Input Monitoring permission required")
                    .fontWeight(.medium)
                Text("Klef cannot detect keyboards without this permission.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()

            Button("Open System Settings") {
                InputMonitoring.openSystemSettingsDeeplink()
            }
        }
        .padding(.vertical, 4)
    }

    /// Shown when permission is granted but HID monitoring is still off — for
    /// example, the user opened Klef before granting access and the first
    /// `IOHIDManagerOpen` failed. Calling `requestHIDStart` re-arms the
    /// manager without restarting the app.
    private var hidStalledBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Klef is not monitoring keyboards")
                    .fontWeight(.medium)
                Text("Permission is granted but the HID manager hasn't started.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()

            Button("Retry") {
                state.onRequestHIDStart?()
            }
        }
        .padding(.vertical, 4)
    }
}
