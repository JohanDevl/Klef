import Foundation

/// A release on GitHub that is newer than the running build.
struct AvailableUpdate: Equatable {
    let version: AppVersion
    let releaseURL: URL

    static func == (lhs: AvailableUpdate, rhs: AvailableUpdate) -> Bool {
        lhs.version == rhs.version && lhs.releaseURL == rhs.releaseURL
    }
}

/// Asks the GitHub Releases API whether a newer version has been published.
///
/// Deliberately *only* a notifier. It does not download, install, or relaunch
/// anything, for a reason specific to Klef: builds are ad-hoc signed, so the
/// binary's CDHash changes on every release, and macOS keys the Input
/// Monitoring grant to that hash. Any update — automatic or manual — revokes
/// the permission Klef needs to do its one job. An in-app updater would land
/// that silently in the background and leave the user with an app that looks
/// fine and does nothing. Sending them to the release page keeps the reinstall,
/// and the re-grant that must follow it, deliberate and visible.
///
/// Revisit once releases are Developer ID signed: a stable signing identity
/// means TCC survives updates, and Sparkle becomes the right answer.
enum UpdateChecker {

    // MARK: - Configuration

    static let repository = "JohanDevl/Klef"

    /// `/releases/latest` skips drafts and pre-releases, which matches the
    /// `draft: false` / `prerelease: false` release-please config.
    private static let endpoint = URL(
        string: "https://api.github.com/repos/\(repository)/releases/latest"
    )!

    /// Klef's release cadence is hand-cut, so a daily check is already generous.
    /// The unauthenticated GitHub API is rate-limited per IP; anything tighter
    /// would be rude for no benefit.
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private static let enabledKey = "klef.updateCheck.enabled"
    private static let lastCheckKey = "klef.updateCheck.lastCheckAt"

    // MARK: - Errors

    enum CheckError: LocalizedError {
        case notBundled
        case rateLimited
        case http(Int)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .notBundled:
                return "Update checks need Klef to run from Klef.app."
            case .rateLimited:
                return "GitHub rate limit reached. Try again later."
            case .http(let code):
                return "GitHub returned HTTP \(code)."
            case .malformedResponse:
                return "Couldn't read GitHub's response."
            }
        }
    }

    // MARK: - Preferences

    /// Opt-out switch. Defaults to enabled; `UserDefaults` returns `false` for
    /// an absent bool, so first-run absence is registered explicitly rather
    /// than read directly.
    static var isEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    static var lastCheckedAt: Date? {
        UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    // MARK: - Checking

    /// Runs a check only if enabled and the interval has elapsed. Used on
    /// launch; silently does nothing otherwise.
    static func checkIfDue(completion: @escaping (Result<AvailableUpdate?, Error>) -> Void) {
        guard isEnabled else { return }
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < checkInterval {
            return
        }
        check(completion: completion)
    }

    /// Runs a check unconditionally. Used by the "Check for Updates" commands.
    /// The completion is always delivered on the main queue.
    ///
    /// A `nil` success value means "checked, nothing newer" — distinct from a
    /// failure, so the UI can tell "you're up to date" from "the check broke".
    static func check(completion: @escaping (Result<AvailableUpdate?, Error>) -> Void) {
        guard let current = AppVersion.current else {
            deliver(.failure(CheckError.notBundled), to: completion)
            return
        }

        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub rejects API requests without a User-Agent.
        request.setValue("Klef/\(current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        // The whole point is freshness; a cached 200 would hide a new release.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let task = session.dataTask(with: request) { data, response, error in
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            if let error {
                deliver(.failure(error), to: completion)
                return
            }

            guard let http = response as? HTTPURLResponse else {
                deliver(.failure(CheckError.malformedResponse), to: completion)
                return
            }

            switch http.statusCode {
            case 200:
                break
            case 404:
                // The repository has no published releases yet. Not an error
                // worth showing anyone — there is simply nothing newer.
                deliver(.success(nil), to: completion)
                return
            case 403, 429:
                deliver(.failure(CheckError.rateLimited), to: completion)
                return
            default:
                deliver(.failure(CheckError.http(http.statusCode)), to: completion)
                return
            }

            guard
                let data,
                let payload = try? JSONDecoder().decode(LatestRelease.self, from: data),
                let latest = AppVersion(payload.tagName),
                let url = URL(string: payload.htmlURL)
            else {
                deliver(.failure(CheckError.malformedResponse), to: completion)
                return
            }

            guard latest > current else {
                Log.info("update check: \(latest) is not newer than \(current)")
                deliver(.success(nil), to: completion)
                return
            }

            Log.info("update check: \(latest) available (running \(current))")
            deliver(.success(AvailableUpdate(version: latest, releaseURL: url)), to: completion)
        }
        task.resume()
    }

    // MARK: - Private helpers

    /// Ephemeral rather than `URLSession.shared`: no cookie store, no credential
    /// store, no on-disk cache. The README promises this request carries nothing
    /// beyond the IP and User-Agent, and this is what makes that literally true
    /// rather than merely true in practice.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    private static func deliver(
        _ result: Result<AvailableUpdate?, Error>,
        to completion: @escaping (Result<AvailableUpdate?, Error>) -> Void
    ) {
        DispatchQueue.main.async { completion(result) }
    }

    /// Only the two fields Klef uses; every other key in the payload is ignored.
    private struct LatestRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
