import AppKit
import SwiftUI

/// Issues mailbox (M16-4 / #185): the repo's open issues over the
/// Keychain bearer, rows opening in the browser, and a create-issue
/// sheet. GitHub-only — Local sources never see the row (the token is
/// in `WorkspaceMailbox.all(for:)`'s github branch only).
///
/// PRs stay out: REST mixes pull requests into `/issues`; `listIssues`
/// filters them (`pull_request == nil`) before this view ever sees them.
struct IssuesMailboxView: View {
    let source: GithubSource

    @State private var issues: [GithubIssue] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showCreateSheet = false

    var body: some View {
        Group {
            if isLoading, issues.isEmpty {
                ProgressView("Loading issues…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText, issues.isEmpty {
                ContentUnavailableView {
                    Label("Issues Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("Try Again") { reload() }
                }
            } else if issues.isEmpty {
                ContentUnavailableView {
                    Label("No Open Issues", systemImage: "exclamationmark.circle")
                } description: {
                    Text("This repository has no open issues.")
                }
                .accessibilityLabel("No Open Issues")
            } else {
                List(issues, id: \.number) { issue in
                    IssueRow(issue: issue) {
                        open(issue)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(source.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Issue…", systemImage: "square.and.pencil")
                }
                .help("Create an issue on \\(source.owner)/\\(source.repository)")
                .disabled(isLoading)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateIssueSheet(source: source) {
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
            let fetched = try await GithubAPIClient.listIssues(
                owner: source.owner,
                repository: source.repository,
                bearer: token,
                transport: transport
            )
            guard !Task.isCancelled else { return }
            issues = fetched
        } catch {
            guard !Task.isCancelled else { return }
            errorText = Self.describe(error)
        }
    }

    private func open(_ issue: GithubIssue) {
        if let url = URL(string: issue.htmlURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Error bodies verbatim (D11) with the needsAuth hint on 401-class
    /// failures — the same posture the Remote mailbox uses.
    static func describe(_ error: Error) -> String {
        if let github = error as? GithubOAuthError {
            switch github {
            case let .httpStatus(status, message):
                var text = "GitHub returned \\(status): \\(message)"
                if status == 401 || status == 403 {
                    text += "\n\nThe token may be revoked or lack `issues` scope. Re-authenticate from Settings → Sources."
                }
                return text
            case .invalidResponse:
                return "GitHub returned an unexpected response."
            case let .deviceCodeFailed(code, message):
                return "\\(code): \\(message)"
            }
        }
        return String(describing: error)
    }
}

/// One issue row: number, title, labels; click opens the issue in the
/// browser (the design's "rows → Open on GitHub").
private struct IssueRow: View {
    let issue: GithubIssue
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\\(issue.number)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                Text(issue.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(issue.labels, id: \.name) { label in
                    IssueLabelChip(label: label)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(issue.htmlURL)
    }
}

/// A label chip colored from GitHub's hex (no `#` prefix as sent).
private struct IssueLabelChip: View {
    let label: GithubIssue.Label

    var body: some View {
        Text(label.name)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
            .lineLimit(1)
    }

    private var backgroundColor: Color {
        Color(nsColor: NSColor(hex: label.color))
    }

    private var foregroundColor: Color {
        // GitHub's hex is mid-tone; white text reads on most labels.
        .white
    }
}

/// Create-issue sheet: title + body over the JSON-post seam, then the
/// mailbox refreshes so the row appears.
private struct CreateIssueSheet: View {
    let source: GithubSource
    /// Runs after a successful create (mailbox refresh).
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Issue")
                .font(.headline)

            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            TextField("Title", text: $title, axis: .vertical)
                .lineLimit(1...2)
                .textFieldStyle(.roundedBorder)
            TextField("Body", text: $bodyText, axis: .vertical)
                .lineLimit(4...8)
                .textFieldStyle(.roundedBorder)

            HStack {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                    Text("Creating…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Issue") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isWorking
                            || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
        }
        .padding(20)
        .frame(width: 460, height: 300)
    }

    private func create() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !isWorking else { return }
        isWorking = true
        errorText = nil
        Task {
            let tokenStore = GithubTokenStore()
            let transport = URLSessionGithubTransport()
            do {
                guard let token = try tokenStore.load() else {
                    throw GithubOAuthError.httpStatus(401, message: "No GitHub token in the Keychain. Re-authenticate from Settings → Sources.")
                }
                defer { token.wipe() }
                let created = try await GithubAPIClient.createIssue(
                    owner: source.owner,
                    repository: source.repository,
                    title: trimmedTitle,
                    body: bodyText,
                    bearer: token,
                    transport: transport
                )
                isWorking = false
                onCreated()
                dismiss()
                if let url = URL(string: created.htmlURL) {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                isWorking = false
                errorText = IssuesMailboxView.describe(error)
            }
        }
    }
}

private extension NSColor {
    /// GitHub sends label colors as `rrggbb` hex without the `#`.
    /// Unparseable input falls back to a neutral gray — never a crash.
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            self.init(calibratedWhite: 0.6, alpha: 1)
            return
        }
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
