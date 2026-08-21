import AppKit
import SwiftUI

/// Pull Requests mailbox (M17-2 / #192): the repo's open pull requests
/// over the Keychain bearer, rows opening in the browser. The read
/// sibling of the M16-4 issues mailbox — github-only (the token is in
/// `WorkspaceMailbox.all(for:)`'s github branch only), API-only (never
/// touches the working copy, so watch is never suspended).
///
/// Uses `listPullRequests` (`/pulls`), not the issues-list filter, so
/// rows carry the draft state and head/base refs a PR mailbox renders.
struct PullRequestsMailboxView: View {
    let source: GithubSource

    @State private var pulls: [GithubPullRequest] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showPRSheet = false

    var body: some View {
        Group {
            if isLoading, pulls.isEmpty {
                ProgressView("Loading pull requests…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText, pulls.isEmpty {
                ContentUnavailableView {
                    Label("Pull Requests Unavailable", systemImage: WorkspaceMailbox.symbolName(WorkspaceMailbox.pulls))
                } description: {
                    Text(errorText)
                } actions: {
                    if errorText.contains("No GitHub token") {
                        Button("Sign In…") {}
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Try Again") { reload() }
                }
            } else if pulls.isEmpty {
                ContentUnavailableView {
                    Label("No Open Pull Requests", systemImage: WorkspaceMailbox.symbolName(WorkspaceMailbox.pulls))
                } description: {
                    Text("This repository has no open pull requests.")
                } actions: {
                    Button("New Pull Request…") { showPRSheet = true }
                        .buttonStyle(.borderedProminent)
                }
                .accessibilityLabel("No Open Pull Requests")
            } else {
                List(pulls, id: \.number) { pr in
                    PullRequestRow(pr: pr) {
                        open(pr)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(source.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPRSheet = true
                } label: {
                    Label("New Pull Request…", systemImage: "arrow.triangle.branch")
                }
                .help("Create a pull request on \(source.owner)/\(source.repository)")
                .disabled(isLoading)
            }
        }
        .sheet(isPresented: $showPRSheet) {
            // The shared M16-3 sheet (M17-3): same flow as the Remote
            // mailbox — push-first when no upstream, POST, open in
            // browser. On success the mailbox refreshes so the new PR
            // appears.
            PullRequestSheet(source: source) {
                Task { await load() }
            }
        }
        .task(id: source.id) {
            await load()
        }
    }

    private func reload() {
        Task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let tokenStore = GithubTokenStore()
        let transport = URLSessionGithubTransport()
        do {
            guard let token = try tokenStore.load() else {
                // The M15 §10 needsAuth posture: non-blocking, re-auth
                // via the existing settings flow. Never a silent retry.
                errorText = "No GitHub token in the Keychain. Re-authenticate from Settings → Sources."
                return
            }
            defer { token.wipe() }
            let fetched = try await GithubAPIClient.listPullRequests(
                owner: source.owner,
                repository: source.repository,
                bearer: token,
                transport: transport
            )
            guard !Task.isCancelled else { return }
            pulls = fetched
        } catch {
            guard !Task.isCancelled else { return }
            errorText = Self.describe(error)
        }
    }

    private func open(_ pr: GithubPullRequest) {
        if let url = URL(string: pr.htmlURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Error bodies verbatim (D11) with the needsAuth hint on 401-class
    /// failures — the same posture the Remote and Issues mailboxes use.
    static func describe(_ error: Error) -> String {
        if let github = error as? GithubOAuthError {
            switch github {
            case let .httpStatus(status, message):
                var text = "GitHub returned \(status): \(message)"
                if status == 401 || status == 403 {
                    text += "\n\nThe token may be revoked or lack `repo` scope (needed to read pull requests). Re-authenticate from Settings → Sources."
                }
                return text
            case .invalidResponse:
                return "GitHub returned an unexpected response."
            case let .deviceCodeFailed(code, message):
                return "\(code): \(message)"
            }
        }
        return String(describing: error)
    }
}

/// One pull request row: number, title, draft badge, head → base;
/// click opens the PR in the browser (the design's "rows → Open on
/// GitHub"). Labels are GitHub's own (`owner:branch` for fork heads).
private struct PullRequestRow: View {
    let pr: GithubPullRequest
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(pr.number)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                Text(pr.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if pr.draft {
                    Text("draft")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                        .help("Draft pull request")
                }
                Text("\(pr.head.label) → \(pr.base.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pr.htmlURL)
    }
}
