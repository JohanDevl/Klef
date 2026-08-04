import AppKit

/// Builds the status-item glyph from an embedded SVG template.
///
/// The source of truth is `Resources/logo/klef-menubar.svg` — this literal is
/// that file's markup with its comment block dropped. It lives in the binary
/// rather than the bundle because the LaunchAgent path
/// (`scripts/install-launch-agent.sh`) runs `.build/*/klef` directly, so
/// `Bundle.main` has no `Contents/Resources` to read from.
///
/// `NSImage` parses SVG natively on macOS 13+, which matches
/// `LSMinimumSystemVersion`.
enum MenuBarIcon {

    /// Menu-bar glyphs are drawn at 18×18 pt; macOS scales for Retina.
    private static let pointSize = NSSize(width: 18, height: 18)

    private static let templateSVG = """
    <svg width="36" height="36" viewBox="0 0 36 36" xmlns="http://www.w3.org/2000/svg">
      <path fill="#000" fill-rule="evenodd" d="
        M13,4 H23 A6.5,6.5 0 0 1 29.5,10.5 V25.5 A6.5,6.5 0 0 1 23,32 H13
          A6.5,6.5 0 0 1 6.5,25.5 V10.5 A6.5,6.5 0 0 1 13,4 Z
        M13.6,6.6 H22.4 A4.5,4.5 0 0 1 26.9,11.1 V24.9 A4.5,4.5 0 0 1 22.4,29.4 H13.6
          A4.5,4.5 0 0 1 9.1,24.9 V11.1 A4.5,4.5 0 0 1 13.6,6.6 Z
        M14.6,14.5 a3.4,3.4 0 1 0 6.8,0 a3.4,3.4 0 1 0 -6.8,0 Z
        M15.3,15.5 H20.7 L19.6,25 H16.4 Z
      "/>
    </svg>
    """

    /// The Klef keycap glyph, or `nil` if the SVG fails to parse.
    ///
    /// Callers fall back to an SF Symbol rather than leaving the status item
    /// blank — an icon-less status item is invisible and unclickable.
    static func makeTemplate() -> NSImage? {
        guard let data = templateSVG.data(using: .utf8),
              let image = NSImage(data: data) else {
            // Without this the SF Symbol fallback is indistinguishable from the
            // pre-brand icon, and the failure leaves no trace anywhere.
            Log.warn("Menu bar SVG failed to parse — falling back to SF Symbol")
            return nil
        }

        image.size = pointSize
        image.isTemplate = true
        image.accessibilityDescription = "Klef"
        return image
    }
}
