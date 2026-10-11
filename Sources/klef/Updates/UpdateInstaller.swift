import AppKit
import CryptoKit
import Foundation

/// Downloads a release's disk image and swaps it in for the running app.
///
/// Runs only when the user clicks Install Update — never on a timer, never in
/// the background. `UpdateChecker` explains why that line matters for Klef.
///
/// The download is untrusted until proven otherwise, and the installed app is
/// the last thing touched:
///
/// 1. refuse up front if the app's location can't be replaced;
/// 2. download, then hold the file to the size and SHA-256 GitHub published;
/// 3. mount it read-only and copy the app next to the installed one;
/// 4. check the copy is the expected Klef, at the expected version, with an
///    intact signature, and able to run on this Mac;
/// 5. only then exchange the two bundles and send the old one to the Trash.
///
/// A failure before step 5 leaves the installed app exactly as it was.
///
/// The SHA-256 comes from the same GitHub release as the image, so it proves
/// the download is the published file — not that the release is genuine.
/// That is the same trust a manual download places in the release page.
enum UpdateInstaller {

    // MARK: - Types

    enum Phase: Equatable {
        case downloading
        case verifying
        case installing
    }

    enum InstallError: LocalizedError {
        case noInstaller
        case translocated
        case notWritable(String)
        case downloadFailed(String)
        case sizeMismatch
        case checksumMismatch
        case unexpectedContents(String)
        case toolFailed(String)
        case rollbackFailed(previousVersionAt: String)

        var errorDescription: String? {
            switch self {
            case .noInstaller:
                return "This release can't be installed from within Klef."
            case .translocated:
                return "Move Klef to the Applications folder, reopen it, then try again."
            case .notWritable(let path):
                return "Klef doesn't have permission to replace \(path)."
            case .downloadFailed(let reason):
                return "The download failed: \(reason)"
            case .sizeMismatch:
                return "The download is incomplete."
            case .checksumMismatch:
                return "The download doesn't match the checksum GitHub published."
            case .unexpectedContents(let reason):
                return "The disk image isn't a usable Klef update: \(reason)"
            case .toolFailed(let reason):
                return reason
            case .rollbackFailed(let path):
                return "The swap failed halfway and Klef could not be put back. The previous version is at \(path)."
            }
        }
    }

    // MARK: - Configuration

    /// The app's name inside the disk image, as `make-dmg.sh` stages it.
    private static let imageAppName = "Klef.app"

    /// Prefixes of the hidden bundles an install creates beside the app: the
    /// staged new version, and the previous one on volumes that can't swap.
    /// Shared with `sweepLeftovers`, which is why they are spelled out once.
    private static let stagedPrefix = ".Klef-update-"
    private static let previousPrefix = ".Klef-previous-"

    private static let installedVersionKey = "klef.update.installedVersion"

    /// `hdiutil` and `codesign` finish in a second or two on a 600 KB image.
    /// Anything near this long is a hang, not slow work.
    private static let toolTimeout: TimeInterval = 120

    // MARK: - Installing

    /// Installs `update` over the app bundle at `target`.
    ///
    /// `onPhase` and `completion` are always delivered on the main queue. On
    /// success the bundle at `target` is the new version and the previous one
    /// is in the Trash; the caller decides when to relaunch.
    static func install(
        _ update: AvailableUpdate,
        replacing target: URL = Bundle.main.bundleURL,
        onPhase: @escaping (Phase) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let finish: (Result<Void, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        let report: (Phase) -> Void = { phase in
            DispatchQueue.main.async { onPhase(phase) }
        }

        guard let asset = update.installer else {
            finish(.failure(InstallError.noInstaller))
            return
        }

        // Before the download, not after: nobody should wait on a transfer
        // that was never going to be installable.
        do {
            try checkReplaceable(target)
        } catch {
            finish(.failure(error))
            return
        }

        var request = URLRequest(url: asset.downloadURL)
        request.setValue(UpdateChecker.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData

        report(.downloading)
        let task = UpdateChecker.session.downloadTask(with: request) { location, response, error in
            let workDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("klef-update-\(UUID().uuidString)", isDirectory: true)
            let image = workDirectory.appendingPathComponent("update.dmg")

            do {
                if let error {
                    throw InstallError.downloadFailed(error.localizedDescription)
                }
                guard let location, let http = response as? HTTPURLResponse else {
                    throw InstallError.downloadFailed("no response from GitHub.")
                }
                guard http.statusCode == 200 else {
                    throw InstallError.downloadFailed("GitHub returned HTTP \(http.statusCode).")
                }

                // URLSession deletes `location` as soon as this handler
                // returns, so the file is claimed here and worked on elsewhere.
                try FileManager.default.createDirectory(
                    at: workDirectory,
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: location, to: image)
            } catch {
                try? FileManager.default.removeItem(at: workDirectory)
                finish(.failure(error))
                return
            }

            // Off the session's delegate queue: it is serial, and mounting and
            // copying would hold up any update check queued behind them.
            DispatchQueue.global(qos: .userInitiated).async {
                defer { try? FileManager.default.removeItem(at: workDirectory) }
                do {
                    report(.verifying)
                    try verify(image, against: asset)

                    report(.installing)
                    try installApp(
                        from: image,
                        expecting: update.version,
                        replacing: target,
                        workDirectory: workDirectory
                    )

                    Log.info("update: installed \(update.version) at \(target.path)")
                    finish(.success(()))
                } catch {
                    finish(.failure(error))
                }
            }
        }
        task.resume()
    }

    // MARK: - Relaunching

    /// Starts the newly installed version and quits this one.
    ///
    /// Records the version first so the next launch knows it follows an update
    /// — see `consumeInstalledVersion`. If the new instance can't be started
    /// this process keeps running and `onFailure` is called on the main queue:
    /// an old Klef that says "quit and reopen me" beats no Klef at all.
    static func relaunch(
        afterInstalling version: AppVersion,
        onFailure: @escaping (Error) -> Void
    ) {
        UserDefaults.standard.set(version.description, forKey: installedVersionKey)

        // As far as LaunchServices knows, this path is the instance already
        // running; without a forced new instance it would only bring that one
        // forward.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            DispatchQueue.main.async {
                if let error {
                    Log.error("update: could not start the new version: \(error.localizedDescription)")
                    onFailure(error)
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// The version an in-app update just installed, if this launch follows
    /// one. Reads once: the marker is cleared so later launches see `nil`.
    static func consumeInstalledVersion() -> AppVersion? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: installedVersionKey) else { return nil }
        defaults.removeObject(forKey: installedVersionKey)
        return AppVersion(raw)
    }

    /// Removes hidden bundles an interrupted install left beside the app.
    ///
    /// Nobody would ever find them to delete by hand. Called at launch, when
    /// no install can be in flight — so whatever carries these prefixes is a
    /// half-staged copy or a version that has already been superseded.
    static func sweepLeftovers(beside target: URL = Bundle.main.bundleURL) {
        guard target.pathExtension == "app" else { return }

        let fileManager = FileManager.default
        let directory = target.deletingLastPathComponent()
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return
        }

        let leftovers = names.filter { name in
            name.hasSuffix(".app")
                && (name.hasPrefix(stagedPrefix) || name.hasPrefix(previousPrefix))
        }
        for name in leftovers {
            do {
                try fileManager.removeItem(at: directory.appendingPathComponent(name))
                Log.info("update: removed leftover \(name)")
            } catch {
                Log.warn("update: could not remove leftover \(name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Steps

    private static func checkReplaceable(_ target: URL) throws {
        // Gatekeeper runs a quarantined app that was never moved out of its
        // download folder from a read-only shadow copy. Replacing that copy
        // would update nothing the user can find again.
        if target.path.contains("/AppTranslocation/") {
            throw InstallError.translocated
        }

        // Advisory only — the kernel has the last word at swap time — but it
        // catches the common cases before anyone waits on a download: the
        // directory to rename within, and the bundle to move to the Trash.
        let fileManager = FileManager.default
        let directory = target.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: directory.path) else {
            throw InstallError.notWritable(directory.path)
        }
        guard fileManager.isWritableFile(atPath: target.path) else {
            throw InstallError.notWritable(target.path)
        }
    }

    private static func verify(_ image: URL, against asset: InstallerAsset) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: image.path)
        guard (attributes[.size] as? NSNumber)?.intValue == asset.size else {
            throw InstallError.sizeMismatch
        }

        let handle = try FileHandle(forReadingFrom: image)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()

        guard digest == asset.sha256 else {
            throw InstallError.checksumMismatch
        }
    }

    private static func installApp(
        from image: URL,
        expecting version: AppVersion,
        replacing target: URL,
        workDirectory: URL
    ) throws {
        let fileManager = FileManager.default

        // An explicit mount point, so there is no hdiutil output to parse and
        // nothing shows up in Finder.
        let mountPoint = workDirectory.appendingPathComponent("mount", isDirectory: true)
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", [
            "attach", image.path,
            "-nobrowse", "-readonly", "-noautoopen",
            "-mountpoint", mountPoint.path,
        ])
        defer { try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        let source = mountPoint.appendingPathComponent(imageAppName, isDirectory: true)
        guard fileManager.fileExists(atPath: source.path) else {
            throw InstallError.unexpectedContents("there is no \(imageAppName) inside.")
        }

        // Staged beside the target rather than in the temp directory: the
        // exchange below then stays on one volume.
        let staged = target.deletingLastPathComponent()
            .appendingPathComponent("\(stagedPrefix)\(UUID().uuidString).app", isDirectory: true)
        // Registered before the copy so a copy that dies halfway is cleaned up
        // too. After a successful exchange this path holds the *previous*
        // version, or nothing once that has gone to the Trash.
        defer { try? fileManager.removeItem(at: staged) }
        try fileManager.copyItem(at: source, to: staged)

        try validate(staged, expecting: version, replacing: target)

        let previous = try exchange(staged, with: target)

        // The Trash rather than a delete: if the new version turns out to be
        // broken, the old one is still one drag away. Deleting is the fallback
        // for volumes with no Trash.
        do {
            try fileManager.trashItem(at: previous, resultingItemURL: nil)
        } catch {
            try? fileManager.removeItem(at: previous)
        }
    }

    /// Confirms the staged copy is the app this update claimed to be, and one
    /// this Mac can run, before it is allowed anywhere near the installed one.
    private static func validate(
        _ staged: URL,
        expecting version: AppVersion,
        replacing target: URL
    ) throws {
        guard let bundle = Bundle(url: staged) else {
            throw InstallError.unexpectedContents("no app bundle inside.")
        }

        guard
            let identifier = bundle.bundleIdentifier,
            identifier == Bundle(url: target)?.bundleIdentifier
        else {
            throw InstallError.unexpectedContents("it holds a different app.")
        }

        guard
            let raw = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            AppVersion(raw) == version
        else {
            throw InstallError.unexpectedContents("its version isn't \(version).")
        }

        // Swapping in a build that can't launch here would trade a working
        // Klef for none, with the working one already in the Trash.
        let system = ProcessInfo.processInfo.operatingSystemVersion
        if let raw = bundle.infoDictionary?["LSMinimumSystemVersion"] as? String,
           let minimum = AppVersion(raw),
           let running = AppVersion("\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"),
           running < minimum {
            throw InstallError.unexpectedContents("it needs macOS \(minimum) or later.")
        }

        #if arch(arm64)
        let architecture = NSBundleExecutableArchitectureARM64
        #else
        let architecture = NSBundleExecutableArchitectureX86_64
        #endif
        guard bundle.executableArchitectures?.contains(NSNumber(value: architecture)) == true else {
            throw InstallError.unexpectedContents("it isn't built for this Mac's processor.")
        }

        // Ad-hoc signatures carry no identity, so this proves the bundle is
        // intact, not who built it. The checksum is what ties it to GitHub.
        do {
            try run("/usr/bin/codesign", ["--verify", "--strict", "--deep", staged.path])
        } catch {
            throw InstallError.unexpectedContents("its code signature doesn't verify.")
        }
    }

    /// Puts `staged` at `target` and returns where the previous bundle now is.
    private static func exchange(_ staged: URL, with target: URL) throws -> URL {
        // One system call that swaps the two names. Both exist before and
        // after, so there is no instant without an app at `target` and nothing
        // to roll back if it fails.
        if renamex_np(staged.path, target.path, UInt32(RENAME_SWAP)) == 0 {
            return staged
        }

        // Volumes that can't swap (anything but APFS): two renames, the first
        // undone if the second fails.
        let fileManager = FileManager.default
        let previous = target.deletingLastPathComponent()
            .appendingPathComponent("\(previousPrefix)\(UUID().uuidString).app", isDirectory: true)
        do {
            try fileManager.moveItem(at: target, to: previous)
        } catch {
            // Nothing has changed yet; the usual cause is permissions.
            throw InstallError.notWritable(target.path)
        }
        do {
            try fileManager.moveItem(at: staged, to: target)
        } catch {
            do {
                try fileManager.moveItem(at: previous, to: target)
            } catch {
                throw InstallError.rollbackFailed(previousVersionAt: previous.path)
            }
            throw error
        }
        return previous
    }

    /// Runs a system tool to completion. Output is discarded rather than piped:
    /// a pipe inherited by a helper the tool leaves behind would never close,
    /// and nothing here needs more than the exit status.
    private static func run(_ tool: String, _ arguments: [String]) throws {
        let name = URL(fileURLWithPath: tool).lastPathComponent

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()

        guard exited.wait(timeout: .now() + toolTimeout) == .success else {
            process.terminate()
            throw InstallError.toolFailed("\(name) did not finish in time.")
        }
        guard process.terminationStatus == 0 else {
            throw InstallError.toolFailed("\(name) failed (exit \(process.terminationStatus)).")
        }
    }
}
