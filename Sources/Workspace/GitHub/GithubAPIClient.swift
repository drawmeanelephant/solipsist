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

/// A created pull request (M16-3 / #185): the number + html URL the
/// sheet opens in the browser.
struct GithubPullRequestCreated: Decodable, Equatable, Sendable {
    let number: Int
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case number
        case htmlURL = "html_url"
    }
}

/// One row of the Pull Requests mailbox (M17 / #192). Full `/pulls`
/// list objects — unlike the shallow issue-mix refs, these carry the
/// draft state and the head/base refs a PR mailbox renders. `head`
/// and `base` use GitHub's own labels: `owner:branch` for head (fork
/// PRs show the fork owner, never a guessed one), plain branch for
/// base.
struct GithubPullRequest: Decodable, Equatable, Sendable {
    struct Ref: Decodable, Equatable, Sendable {
        /// `owner:branch` for head (fork PRs), `branch` for base.
        let label: String
        let ref: String
    }

    let number: Int
    let title: String
    let htmlURL: String
    /// Open draft PRs are included by `state=open`; the mailbox badges them.
    let draft: Bool
    let state: String
    let head: Ref
    let base: Ref

    enum CodingKeys: String, CodingKey {
        case number, title, draft, state, head, base
        case htmlURL = "html_url"
    }
}

/// One row of the issues mailbox (M16-4 / #185). REST returns pull
/// requests mixed into the issues list — `pullRequest` is present
/// exactly for those, so the mailbox filters `== nil` and PRs never
/// appear as issues. `labels` is a minimal name + color for chips.
struct GithubIssue: Decodable, Equatable, Sendable {
    struct Label: Decodable, Equatable, Sendable {
        let name: String
        /// Hex color without the leading `#`, as GitHub sends it.
        let color: String
    }

    struct PullRequestRef: Decodable, Equatable, Sendable {
        let url: String
    }

    let number: Int
    let title: String
    let htmlURL: String
    let labels: [Label]
    /// Non-nil exactly when this row is a pull request, not an issue.
    let pullRequest: PullRequestRef?

    var isPullRequest: Bool { pullRequest != nil }

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case htmlURL = "html_url"
        case labels
        case pullRequest = "pull_request"
    }
}

/// Minimal GitHub REST surface (M15 / #179, M16 / #185): identity,
/// repo default branch, PR creation. Boris has no GitHub API — the app
/// owns this. Tokens ride as `SecureBuffer`; the transport builds the
/// Authorization header. Error bodies surface as
/// `GithubOAuthError.httpStatus`, never swallowed.
enum GithubAPIClient {
    static let userURL = URL(string: "https://api.github.com/user")!

    static func repositoryURL(owner: String, repository: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)")!
    }

    static func pullsURL(owner: String, repository: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/pulls")!
    }

    /// `GET /repos/{owner}/{repo}/pulls?state=…` — the PR mailbox
    /// list endpoint (M17-1). The POST target stays plain `pullsURL`.
    static func listPullsURL(owner: String, repository: String, state: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/pulls?state=\(state)")!
    }

    /// `GET /repos/{owner}/{repo}/issues?state=open` — REST returns PRs
    /// in the same list; `listIssues` filters them out (M16-4).
    static func issuesURL(owner: String, repository: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/issues?state=open")!
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

    /// Create a pull request: `POST /repos/{owner}/{repo}/pulls` with
    /// the Keychain bearer. `head` is the source branch, `base` the
    /// target (defaults to `defaultBranch` in the sheet). The response
    /// carries `number` + `html_url`. Non-2xx bodies surface as
    /// `httpStatus(status, message)` — never swallowed (D11).
    static func createPullRequest(
        owner: String,
        repository: String,
        title: String,
        body: String,
        head: String,
        base: String,
        bearer: SecureBuffer,
        transport: GithubOAuth.HTTPTransport
    ) async throws -> GithubPullRequestCreated {
        let payload: [String: String] = [
            "title": title,
            "body": body,
            "head": head,
            "base": base,
        ]
        let data = try await transport.post(
            pullsURL(owner: owner, repository: repository),
            json: jsonBody(payload),
            bearer: bearer
        )
        return try decode(GithubPullRequestCreated.self, from: data)
    }

    /// Open issues for the repo (M16-4): `GET …/issues?state=open`,
    /// with pull requests filtered out of the REST mix. Rows carry
    /// `htmlURL` so the mailbox opens them in the browser.
    static func listIssues(
        owner: String,
        repository: String,
        bearer: SecureBuffer,
        transport: GithubOAuth.HTTPTransport
    ) async throws -> [GithubIssue] {
        let data = try await transport.get(
            issuesURL(owner: owner, repository: repository),
            bearer: bearer
        )
        let issues = try decode([GithubIssue].self, from: data)
        return issues.filter { !$0.isPullRequest }
    }

    /// Open pull requests for the repo (M17-1 / #192): `GET
    /// …/pulls?state=open` over the bearer-`get` seam. Uses the proper
    /// `/pulls` endpoint — not the issues-list `pull_request` filter —
    /// so rows carry draft + head/base. `state` defaults to `open` (the
    /// mailbox's honest default, mirroring the issues mailbox); the
    /// param exists for tests and a future closed/all toggle.
    static func listPullRequests(
        owner: String,
        repository: String,
        state: String = "open",
        bearer: SecureBuffer,
        transport: GithubOAuth.HTTPTransport
    ) async throws -> [GithubPullRequest] {
        let data = try await transport.get(
            listPullsURL(owner: owner, repository: repository, state: state),
            bearer: bearer
        )
        return try decode([GithubPullRequest].self, from: data)
    }

    /// Create an issue (M16-4): `POST …/issues` with title + body over
    /// the JSON-post seam. Returns the created issue (number + html URL).
    static func createIssue(
        owner: String,
        repository: String,
        title: String,
        body: String,
        bearer: SecureBuffer,
        transport: GithubOAuth.HTTPTransport
    ) async throws -> GithubIssue {
        let payload: [String: String] = [
            "title": title,
            "body": body,
        ]
        let data = try await transport.post(
            issuesURL(owner: owner, repository: repository),
            json: jsonBody(payload),
            bearer: bearer
        )
        return try decode(GithubIssue.self, from: data)
    }

    private static func jsonBody(_ object: [String: String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GithubOAuthError.invalidResponse
        }
    }
}
