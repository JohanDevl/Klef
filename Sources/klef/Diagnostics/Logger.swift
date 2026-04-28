import Foundation

/// Minimal level-based logger for V0.1.
///
/// Routing policy:
/// - `info`  → stdout — diagnostic context (manager started, matched device, …)
/// - `warn`  → stderr — recoverable concerns (permission unknown, …)
/// - `error` → stderr — failures (manager open failed, …)
/// - `event` → stdout — per-dominance-change hot path; designed for piping
///
/// CLI banner output (the program name, "Press Ctrl-C", "Enabled keyboard
/// input sources:" header) is NOT routed through Log — that's user-facing
/// presentation, not diagnostics. All other diagnostic output goes through
/// this enum so the V1 OSLog migration (PRD FR-7) is a single-file swap.
///
/// Timestamps use ISO-8601 with millisecond precision.
enum Log {
    // MARK: - Timestamp

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func timestamp() -> String {
        formatter.string(from: Date())
    }

    // MARK: - Public interface

    static func info(_ message: @autoclosure () -> String) {
        print("[\(timestamp())] INFO  \(message())")
    }

    static func warn(_ message: @autoclosure () -> String) {
        fputs("[\(timestamp())] WARN  \(message())\n", stderr)
    }

    static func error(_ message: @autoclosure () -> String) {
        fputs("[\(timestamp())] ERROR \(message())\n", stderr)
    }

    /// Emitted on each dominant-device change. Goes to stdout so callers can
    /// pipe events independently from diagnostic noise on stderr.
    static func event(_ message: @autoclosure () -> String) {
        print("[\(timestamp())] EVENT \(message())")
    }

    // MARK: - Redaction (PRD FR-7)

    /// Replaces a trailing serial-like token with `[redacted]`. Conservative:
    /// only matches a final run of 6+ alphanumeric characters that contains
    /// at least one digit and is preceded by whitespace, dash, hash, colon,
    /// or en-dash. Names like "Magic Keyboard – ABCD12" become
    /// "Magic Keyboard – [redacted]"; names like "Apple Internal Keyboard /
    /// Trackpad" are left intact.
    static func redactSerialLike(_ name: String) -> String {
        let pattern = #"(?<=[\s\-:#–])([A-Za-z0-9]{6,})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return name }
        let nsRange = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, range: nsRange),
              let range = Range(match.range, in: name),
              name[range].contains(where: \.isNumber)
        else { return name }
        return name.replacingCharacters(in: range, with: "[redacted]")
    }
}
