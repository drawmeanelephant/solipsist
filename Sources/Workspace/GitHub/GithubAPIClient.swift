import Foundation

/// The authenticated user, from `GET /user`. `name` is optional — not
/// every account sets one.
struct GithubUser: Decodable, Equatable, Sendable {
    let login: String
    let name: String?
    let id: Int
}

/// Repository identity from `GET /repos/{owner}/{repo}`: the default
/// branch comes from the remote, never guessed (M15).
struct GithubRepositoryInfo: Decodable, Equatable, Sendable {
    let fullName: String
    let defaultBranch: String
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case defaultBranch = "default_branch"
        case isPrivate = "private"
    }
}

/// Minimal GitHub REST surface (M15 / #179): identity + repo default
/// branch. Boris has no GitHub API — the app owns this. Tokens ride as
/// `SecureBuffer`; the transport builds the Authorization header. Error
/// bodies surface as `GithubOAuthError.httpStatus`, never swallowed.
enum GithubAPIClient {
    static let userURL = URL(string: "https://api.github.com/user")!

    static func repositoryURL(owner: String, repository: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)")!
    }

    static func user(bearer: SecureBuffer, transport: GithubOAuth.HTTPTransport) async throws -> GithubUser {
        let data = try await transport.get(userURL, bearer: bearer)
        return try decode(GithubUser.self, from: data)
    }

    static func repository(
        owner: String,
        repository: String,
        bearer: SecureBuffer,
        transport: GithubOAuth.HTTPTransport
    ) async throws -> GithubRepositoryInfo {
        let data = try await transport.get(
            repositoryURL(owner: owner, repository: repository),
            bearer: bearer
        )
        return try decode(GithubRepositoryInfo.self, from: data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GithubOAuthError.invalidResponse
        }
    }
}
