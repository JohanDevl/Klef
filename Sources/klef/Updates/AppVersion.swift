import Foundation

/// A dot-separated release version, ordered by comparing components numerically.
///
/// This type exists so the obvious mistake can't be made at a call site: string
/// comparison sorts `"0.10.0"` *before* `"0.9.0"`, which would silently stop
/// offering updates the moment the minor version reaches double digits.
struct AppVersion: Comparable, CustomStringConvertible {

    /// Numeric components, most significant first. `1.2.3` → `[1, 2, 3]`.
    let components: [Int]

    /// Normalised text form, without any leading `v`.
    let description: String

    /// Parses `1.2.3`, tolerating a leading `v` — release-please tags releases
    /// as `v0.3.0` while `CFBundleShortVersionString` holds a bare `0.3.0`, and
    /// both feed into this initialiser.
    ///
    /// Any suffix past the numeric core (`-beta.1`, `+build.7`) is dropped:
    /// Klef cuts releases without pre-release identifiers, so ordering within a
    /// pre-release series is not something this needs to model.
    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }

        let core = String(text.prefix { $0.isNumber || $0 == "." })
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var parsed: [Int] = []
        parsed.reserveCapacity(parts.count)
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            parsed.append(value)
        }

        self.components = parsed
        self.description = core
    }

    /// The running app's version, read from the bundle.
    ///
    /// `nil` when Klef runs as a bare binary out of `.build/` rather than from
    /// `Klef.app` — there is no Info.plist to read. Callers treat that as
    /// "can't compare", which correctly disables update checks for dev builds.
    static var current: AppVersion? {
        guard let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return AppVersion(raw)
    }

    // MARK: - Comparable

    /// Missing trailing components read as zero, so `1.2` and `1.2.0` compare
    /// equal rather than ordering by length.
    private static func component(_ version: AppVersion, at index: Int) -> Int {
        index < version.components.count ? version.components[index] : 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = component(lhs, at: index)
            let right = component(rhs, at: index)
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width where component(lhs, at: index) != component(rhs, at: index) {
            return false
        }
        return true
    }
}
