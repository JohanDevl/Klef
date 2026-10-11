import AppKit
import SwiftUI

/// Credits, license, and project links, as rows of the Settings form.
///
/// Everything here is static or read from the bundle. The links hand off to
/// the default browser; Klef itself fetches nothing. The README promises the
/// update check is the app's only network request, and an avatar or badge
/// loaded here would quietly break that.
struct AboutView: View {

    @State private var isShowingLicense = false

    private static let authorName = "Johan Devlaminck"

    /// `NSHumanReadableCopyright` from Info.plist, so the notice is written
    /// down once. Absent when Klef runs as a bare binary out of `.build/`.
    private static let copyright: String =
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "MIT License"

    /// The full license text, copied into the bundle by `bundle-app.sh`.
    /// `nil` for unbundled dev builds, which fall back to the copy on GitHub.
    private static let licenseText: String? = {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    var body: some View {
        header

        LabeledContent("Created by") {
            Link(Self.authorName, destination: ProjectLinks.author)
        }

        LabeledContent("License") {
            HStack(spacing: 8) {
                Text(Self.copyright)
                    .foregroundStyle(.secondary)

                Button("View License") {
                    if Self.licenseText == nil {
                        NSWorkspace.shared.open(ProjectLinks.license)
                    } else {
                        isShowingLicense = true
                    }
                }
            }
        }
        // Attached to this row, not to the whole body: a modifier on a
        // multi-row body is applied to every row, which would present one
        // sheet per row off the same flag.
        .sheet(isPresented: $isShowingLicense) {
            licenseSheet(Self.licenseText ?? "")
        }

        LabeledContent("Project") {
            HStack(spacing: 14) {
                Link("GitHub Repository", destination: ProjectLinks.repository)
                Link("Releases", destination: ProjectLinks.releases)
                Link("Report an Issue", destination: ProjectLinks.issues)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Klef")
                    .font(.headline)
                Text("Per-keyboard automatic input source switching for macOS.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }

    private func licenseSheet(_ text: String) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Done") {
                isShowingLicense = false
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        // Escape closes the sheet too, as on any other read-only macOS sheet.
        .onExitCommand { isShowingLicense = false }
        // No wider than the Settings window's minimum width, so the sheet
        // never overhangs the window it is attached to.
        .frame(width: 520, height: 420)
    }
}
