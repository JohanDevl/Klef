import Foundation

/// A release on GitHub that is newer than the running build.
struct AvailableUpdate: Equatable {
    let version: AppVersion
    let releaseURL: URL

    /// The release's disk image, when Klef can install it in place. `nil`
    /// leaves the release page as the only route — see `InstallerAsset`.
    let installer: InstallerAsset?
}

/// A release's disk image, and what the download has to match before
/// `UpdateInstaller` will touch it.
struct InstallerAsset: Equatable {
    let downloadURL: URL
    let size: Int
    /// Lowercase hex. GitHub computes it when the asset is uploaded.
    let sha256: String
}

/// Asks the GitHub Releases API whether a newer version has been published.
///
/// Deliberately *only* a notifier: it reports what exists and never acts on
/// it. Installing is a separate step — `UpdateInstaller`, run when the user
/// clicks Install Update — for a reason specific to Klef: builds are ad-hoc
/// signed, so the binary's CDHash changes on every release, and macOS keys the
/// Input Monitoring grant to that hash. Any update revokes the permission Klef
/// needs to do its one job. One landed silently in the background would leave
/// the user with an app that looks fine and does nothing; one they asked for
/// can walk them straight to the re-grant that must follow it.
///
/// Revisit once releases are Developer ID signed: a stable signing identity
/// means TCC survives updates, and background updates become reasonable.
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

    /// Sent with every request Klef makes; GitHub rejects API calls without
    /// one. Carries the version and nothing else.
    static var userAgent: String {
        "Klef/\(AppVersion.current?.description ?? "dev")"
    }

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
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
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
            let update = AvailableUpdate(
                version: latest,
                releaseURL: url,
                installer: installerAsset(in: payload.assets)
            )
            deliver(.success(update), to: completion)
        }
        task.resume()
    }

    // MARK: - Session

    /// Ephemeral rather than `URLSession.shared`: no cookie store, no credential
    /// store, no on-disk cache. The README promises Klef's requests carry
    /// nothing beyond the IP and User-Agent, and this is what makes that
    /// literally true rather than merely true in practice. Shared with
    /// `UpdateInstaller` so the download keeps the same promise.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    // MARK: - Private helpers

    /// The disk image Klef is willing to install, or `nil`.
    ///
    /// Strict on purpose, because whatever this returns gets downloaded and
    /// swapped in for the running app: exactly one `.dmg`, served from this
    /// repository's own release downloads over HTTPS, with a SHA-256 digest to
    /// hold the download to. Anything less falls back to the release page.
    private static func installerAsset(in assets: [LatestRelease.Asset]) -> InstallerAsset? {
        let images = assets.filter { $0.name?.hasSuffix(".dmg") == true }
        let digestPrefix = "sha256:"
        guard
            images.count == 1,
            let image = images.first,
            let size = image.size,
            let digest = image.digest,
            digest.hasPrefix(digestPrefix),
            let url = image.browserDownloadURL.flatMap(URL.init(string:)),
            url.scheme == "https",
            url.host == "github.com",
            url.path.hasPrefix("/\(repository)/releases/download/")
        else {
            return nil
        }

        let hex = digest.dropFirst(digestPrefix.count).lowercased()
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }

        return InstallerAsset(downloadURL: url, size: size, sha256: hex)
    }

    private static func deliver(
        _ result: Result<AvailableUpdate?, Error>,
        to completion: @escaping (Result<AvailableUpdate?, Error>) -> Void
    ) {
        DispatchQueue.main.async { completion(result) }
    }

    /// Only the fields Klef uses; every other key in the payload is ignored.
    private struct LatestRelease: Decodable {
        let tagName: String
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }

        /// The assets only matter to the in-app install. However odd they
        /// look, they must never cost the user the notification itself, so
        /// they decode leniently and `installerAsset` does the judging.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tagName = try container.decode(String.self, forKey: .tagName)
            htmlURL = try container.decode(String.self, forKey: .htmlURL)
            assets = (try? container.decode([Asset].self, forKey: .assets)) ?? []
        }

        struct Asset: Decodable {
            let name: String?
            let size: Int?
            let browserDownloadURL: String?
            /// `sha256:<hex>`. Absent on assets uploaded before GitHub started
            /// computing digests.
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name
                case size
                case browserDownloadURL = "browser_download_url"
                case digest
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try? container.decode(String.self, forKey: .name)
                size = try? container.decode(Int.self, forKey: .size)
                browserDownloadURL = try? container.decode(String.self, forKey: .browserDownloadURL)
                digest = try? container.decode(String.self, forKey: .digest)
            }
        }
    }
}
