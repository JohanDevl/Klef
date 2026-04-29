import Foundation

/// UserDefaults adapter for the device-mapping dictionary.
///
/// Persists a versioned JSON container under a single key.  Schema versioning
/// prevents crashes if a future version writes an incompatible format — this
/// version returns `[:]` and logs a warning rather than crashing.
final class MappingsStore {

    // MARK: - Private types

    private struct Container: Codable {
        let schemaVersion: Int
        let entries: [String: DeviceMappingEntry]
    }

    private static let currentSchemaVersion = 1

    // MARK: - Private state

    private let defaults: UserDefaults
    private let key: String

    // MARK: - Init

    init(defaults: UserDefaults = .standard, key: String = "klef.mappings.v1") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: - Public API

    /// Loads the persisted mapping dictionary.
    ///
    /// Returns an empty dictionary on first launch, decode failure, or unknown
    /// schema version — never throws or crashes.
    func load() -> [String: DeviceMappingEntry] {
        guard let data = defaults.data(forKey: key) else { return [:] }

        do {
            let container = try JSONDecoder().decode(Container.self, from: data)
            guard container.schemaVersion == Self.currentSchemaVersion else {
                Log.warn("MappingsStore: unknown schemaVersion \(container.schemaVersion) — discarding persisted mappings")
                return [:]
            }
            return container.entries
        } catch {
            Log.warn("MappingsStore: failed to decode persisted mappings (\(error)) — starting fresh")
            return [:]
        }
    }

    /// Persists the mapping dictionary to UserDefaults.
    func save(_ entries: [String: DeviceMappingEntry]) {
        let container = Container(schemaVersion: Self.currentSchemaVersion, entries: entries)
        do {
            let data = try JSONEncoder().encode(container)
            defaults.set(data, forKey: key)
        } catch {
            Log.error("MappingsStore: failed to encode mappings (\(error))")
        }
    }
}
