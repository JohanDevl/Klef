import AppKit
import SwiftUI

/// Update-check preferences, manual trigger, and the in-app install.
///
/// The opt-out toggle is deliberate rather than a nicety. Klef asks for Input
/// Monitoring, so it earns trust by making every outbound request visible and
/// refusable — the README's privacy section promises exactly that, and this is
/// where the promise is kept. Installing follows the same rule: it starts from
/// a button, behind a confirmation that says what it will cost.
struct UpdateCheckView: View {

    @EnvironmentObject var state: AppState

    /// Mirrors `UpdateChecker.isEnabled`, which lives in UserDefaults rather
    /// than `AppState` — the checker reads it before any state object exists.
    @State private var automaticChecks: Bool = UpdateChecker.isEnabled

    @State private var isConfirmingInstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { automaticChecks },
                set: { newValue in
                    automaticChecks = newValue
                    state.setUpdateChecksEnabled(newValue)
                }
            ))
            .toggleStyle(.switch)
            .disabled(state.isInstallingUpdate)
            .help("Asks GitHub once a day whether a newer release exists. Downloads nothing.")

            HStack(spacing: 8) {
                Text(versionLine)
                    .foregroundStyle(.secondary)
                    .font(.callout)

                Spacer()

                Button("Check Now") {
                    state.checkForUpdates(explicit: true)
                }
                .disabled(state.isCheckingForUpdate || state.isInstallingUpdate)
            }

            if let update = state.availableUpdate {
                updateAvailableHint(update)
            } else if let message = state.updateCheckMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    private var versionLine: String {
        guard let current = AppVersion.current else {
            return "Running an unbundled build \u{2014} updates unavailable."
        }
        return "Current version \(current)."
    }

    private func updateAvailableHint(_ update: AvailableUpdate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)

                Text("Klef \(update.version.description) is available.")
                    .foregroundStyle(.secondary)
                    .font(.callout)

                Spacer()

                if update.installer == nil {
                    Button("Open Download Page") {
                        NSWorkspace.shared.open(update.releaseURL)
                    }
                } else {
                    Button("Release Notes") {
                        NSWorkspace.shared.open(update.releaseURL)
                    }

                    Button("Install Update") {
                        isConfirmingInstall = true
                    }
                    .disabled(!state.updateInstallState.allowsNewInstall)
                }
            }

            installStatus

            // Klef's builds are ad-hoc signed, so the updated binary has a new
            // CDHash and macOS drops the Input Monitoring grant on install.
            // Saying so here is what keeps an update from looking like a bug.
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)

                Text("After installing, re-grant Input Monitoring \u{2014} macOS revokes it whenever the app binary changes.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .alert(
            "Install Klef \(update.version.description)?",
            isPresented: $isConfirmingInstall
        ) {
            Button("Install") {
                state.installUpdate()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Klef will download the update, replace itself and reopen. macOS then revokes Input Monitoring, so you will need to grant it again in System Settings.")
        }
    }

    @ViewBuilder
    private var installStatus: some View {
        switch state.updateInstallState {
        case .idle:
            EmptyView()

        case .working(let phase):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text(Self.label(for: phase))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)

                Text("Update not installed. \(message)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

        case .restartRequired(let version):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text("Klef \(version.description) is installed. Quit Klef and open it again to finish.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    private static func label(for phase: UpdateInstaller.Phase) -> String {
        switch phase {
        case .downloading: return "Downloading the update\u{2026}"
        case .verifying: return "Verifying the download\u{2026}"
        case .installing: return "Installing\u{2026}"
        }
    }
}
