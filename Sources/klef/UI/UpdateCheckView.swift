import AppKit
import SwiftUI

/// Update-check preferences and manual trigger.
///
/// The opt-out toggle is deliberate rather than a nicety. Klef asks for Input
/// Monitoring, so it earns trust by making every outbound request visible and
/// refusable — the README's privacy section promises exactly that, and this is
/// where the promise is kept.
struct UpdateCheckView: View {

    @EnvironmentObject var state: AppState

    /// Mirrors `UpdateChecker.isEnabled`, which lives in UserDefaults rather
    /// than `AppState` — the checker reads it before any state object exists.
    @State private var automaticChecks: Bool = UpdateChecker.isEnabled

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
            .help("Asks GitHub once a day whether a newer release exists. Downloads nothing.")

            HStack(spacing: 8) {
                Text(versionLine)
                    .foregroundStyle(.secondary)
                    .font(.callout)

                Spacer()

                Button("Check Now") {
                    state.checkForUpdates(explicit: true)
                }
                .disabled(state.isCheckingForUpdate)
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

                Button("Open Download Page") {
                    NSWorkspace.shared.open(update.releaseURL)
                }
            }

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
    }
}
