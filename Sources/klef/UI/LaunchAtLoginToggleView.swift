import AppKit
import ServiceManagement
import SwiftUI

/// Toggle bound to `SMAppService.mainApp` (the Login Items system).
///
/// Reads live from the system on appear and whenever the Settings window
/// becomes key, so the UI stays in sync if the user changes the setting in
/// System Settings → General → Login Items. Uses a custom `Binding` rather
/// than `@State` + `.onChange` to avoid reentrancy when programmatic syncs
/// rewrite the toggle's value.
struct LaunchAtLoginToggleView: View {

    @State private var status: SMAppService.Status = .notRegistered
    @State private var errorMessage: String?

    /// User-expressed intent that hasn't yet been reflected in `status` —
    /// notably the `.requiresApproval` window between calling `register()`
    /// and the user approving in System Settings. Cleared once the system
    /// settles into `.enabled` / `.notRegistered` / `.notFound`.
    @State private var pendingIntent: Bool?

    private let didBecomeKey = NotificationCenter.default.publisher(
        for: NSWindow.didBecomeKeyNotification
    )

    private var isOn: Bool {
        if let pendingIntent { return pendingIntent }
        return status == .enabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at Login", isOn: Binding(
                get: { isOn },
                set: { apply($0) }
            ))
            .toggleStyle(.switch)
            .help("Start Klef automatically when you log in.")

            if status == .requiresApproval, isOn {
                approvalHint
            } else if status == .notFound {
                notFoundHint
            }

            if let errorMessage {
                errorHint(errorMessage)
            }
        }
        .padding(.vertical, 4)
        .onAppear { sync() }
        .onReceive(didBecomeKey) { _ in sync() }
    }

    // MARK: - Subviews

    private var approvalHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text("Approve Klef in Login Items to enable launch at login.")
                .foregroundStyle(.secondary)
                .font(.callout)

            Spacer()

            Button("Open Login Items") {
                LaunchAtLogin.openSystemSettingsDeeplink()
            }
        }
    }

    /// Shown when `SMAppService.mainApp` cannot locate Klef's bundle —
    /// typically because the app is running from a build directory rather than
    /// `/Applications`, or because code-signing metadata is missing.
    private var notFoundHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)

            Text("Move Klef to /Applications and relaunch to enable launch at login.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private func errorHint(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)

            Text(message)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    // MARK: - State management

    private func sync() {
        status = LaunchAtLogin.status
        // Drop pending intent once the system has settled into a definite state.
        if status != .requiresApproval {
            pendingIntent = nil
        }
    }

    private func apply(_ newValue: Bool) {
        errorMessage = nil
        pendingIntent = newValue
        do {
            try LaunchAtLogin.setEnabled(newValue)
            status = LaunchAtLogin.status
            if status != .requiresApproval {
                pendingIntent = nil
            }
        } catch {
            errorMessage = "Couldn't update Launch at Login: \(error.localizedDescription)"
            pendingIntent = nil
            status = LaunchAtLogin.status
        }
    }
}
