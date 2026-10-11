import Foundation

/// Where Klef lives on GitHub.
///
/// The repository URLs are derived from `UpdateChecker.repository` rather than
/// spelled out a second time, so the update check and these links can never
/// point at different repositories.
enum ProjectLinks {
    static let repository = URL(string: "https://github.com/\(UpdateChecker.repository)")!
    static let releases = repository.appendingPathComponent("releases")
    static let issues = repository.appendingPathComponent("issues")
    static let license = repository.appendingPathComponent("blob/main/LICENSE")

    /// Spelled out rather than derived from the repository owner: who wrote
    /// Klef stays true even if the repository moves to another account.
    static let author = URL(string: "https://github.com/JohanDevl")!
}
