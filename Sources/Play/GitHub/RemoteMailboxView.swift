import AppKit
import SwiftUI

/// Remote mailbox (M15 / #179): the read-only sync state of a GitHub
/// working copy — branch, ahead/behind against the upstream, last sync
/// time, the **Sync** verb (fetch + `pull --ff-only` through the
/// credential helper), and **Open on GitHub**. Watch is suspended for
/// the pull (the working copy is the tree watch serves) and resumed
/// after, exactly like play's own IR builds.
struct RemoteMailboxView: View {
    let source: GithubSource

    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime

    @State private var status: GitClone.GitBranchStatus?
    @State private var statusError: String?
    @State private var showCommitSheet = false
    @State private var showPRSheet = false
    @State private var isPushing = false

    var body: some View {
        List {
            syncSection
            commitSection
            pushSection
            prSection
            statusSection
            if let error = live.lastSyncError {
                Section {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                } header: {
                    Text("Last Sync Failed")
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle(source.title)
        .task(id: source.id) {
            await refreshStatus()
        }
        .onChange(of: live.isSyncing) { _, syncing in
            guard !syncing else { return }
            Task { await refreshStatus() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openOnGitHub) {
                    Label("Open on GitHub", systemImage: "arrow.up.right.square")
                }
                .help("Open \\(source.owner)/\\(source.repository) in your browser")
            }
        }
        .sheet(isPresented: $showCommitSheet) {
            CommitSheet(source: source) {
                Task { await refreshStatus() }
            }
        }
        .sheet(isPresented: $showPRSheet) {
            PullRequestSheet(source: source) {
                Task { await refreshStatus() }
            }
        }
    }

    private var commitSection: some View {
        Section {
            HStack {
                Label("Commit", systemImage: "square.and.pencil")
                Spacer()
                Button("Commit…") {
                    showCommitSheet = true
                }
                .disabled(!live.isAvailable || live.isSyncing)
            }
        }
    }

    private var pushSection: some View {
        Section {
            HStack {
                if isPushing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Pushing…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { store.cancelPushGithub(source.id) }
                } else {
                    Label("Push", systemImage: "paperplane")
                    Spacer()
                    Button("Push") {
                        push()
                    }
                    .disabled(!live.isAvailable || live.isSyncing || (status?.ahead ?? 0) == 0)
                }
            }
        }
    }

    private var prSection: some View {
        Section {
            HStack {
                Label("Pull Request", systemImage: "arrow.triangle.branch")
                Spacer()
                Button("New Pull Request…") {
                    showPRSheet = true
                }
                .disabled(!live.isAvailable || live.isSyncing || status?.branch == nil)
            }
        }
    }

    /// The store's live copy — reflects isSyncing / lastSyncError as the
    /// store mutates it, so the button spins and errors surface.
    private var live: GithubSource {
        if case .github(let github) = store.selectedSource, github.id == source.id {
            return github
        }
        return source
    }

    private var syncSection: some View {
        Section {
            HStack {
                if live.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { store.cancelSyncGithub(source.id) }
                } else {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Button("Sync") {
                        sync()
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Branch") {
                Text(status?.branch ?? "—")
                    .monospaced()
            }
            LabeledContent("Ahead") {
                Text("\\(status?.ahead ?? 0) commit\\(status?.ahead == 1 ? \"\" : \"s\")")
            }
            LabeledContent("Behind") {
                Text("\\(status?.behind ?? 0) commit\\(status?.behind == 1 ? \"\" : \"s\")")
            }
            LabeledContent("Default Branch") {
                Text(source.defaultBranch)
                    .monospaced()
            }
            if let lastSyncedAt = live.lastSyncedAt {
                LabeledContent("Last Synced") {
                    Text(lastSyncedAt, style: .relative)
                }
            }
            if let lastPushedAt = live.lastPushedAt {
                LabeledContent("Last Pushed") {
                    Text(lastPushedAt, style: .relative)
                }
            }
            if let branch = status?.branch, let upstream = status?.upstream {
                LabeledContent("Upstream") {
                    Text(upstream)
                        .monospaced()
                }
            }
            if let statusError {
                Text(statusError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private func sync() {
        guard !live.isSyncing else { return }
        Task {
            // The pull rewrites the tree watch serves: freeze it for the
            // sync, thaw after (COORDINATOR.md §3 primitives).
            runtime.coordinator.beginTreeWrite()
            defer { runtime.coordinator.endTreeWrite() }
            await store.syncGithub(source.id)
        }
    }

    private func push() {
        guard !isPushing else { return }
        isPushing = true
        Task {
            // Push touches only the remote + tracking refs, never the
            // content tree — watch keeps running (design §2).
            let result = await store.pushGithub(source.id)
            isPushing = false
            if !result.isSuccess {
                statusError = Self.describePush(result)
            }
            await refreshStatus()
        }
    }

    /// Git's exit + stderr verbatim; a needsAuth hint on 401-class
    /// failures (M15 §10 posture — re-auth via the settings flow).
    static func describePush(_ result: GithubCommit.CommitResult) -> String {
        var text = "git push failed (exit \(result.exitCode)): \(result.stderr)"
        if result.stderr.contains("401") || result.stderr.contains("403") || result.stderr.contains("Authentication failed") {
            text += "\n\nThe token may be revoked or lack `repo` scope. Re-authenticate from Settings → Sources."
        }
        return text
    }

    private func openOnGitHub() {
        NSWorkspace.shared.open(source.remoteURL)
    }

    @MainActor
    private func refreshStatus() async {
        status = nil
        statusError = nil
        guard let root = try? source.workspaceRoot() else {
            statusError = "Working copy is unavailable."
            return
        }
        let result = await Task.detached {
            GitClone.branchStatus(at: root)
        }.value
        status = result
    }
}

/// Commit picker (M16-1): changed files with checkboxes, a message, and
/// a Commit button. Exactly the picked paths are staged — never
/// `git add -A`. Identity is never invented: git's missing-identity
/// error surfaces verbatim with a repo-config hint.
private struct CommitSheet: View {
    let source: GithubSource
    /// Runs after a successful commit (branchStatus refresh).
    let onCommitted: () -> Void

    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [GitClone.GitStatusEntry] = []
    @State private var selectedPaths: Set<String> = []
    @State private var message = ""
    @State private var isCommitting = false
    @State private var commitError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Commit Changes")
                .font(.headline)

            if let commitError {
                Text(commitError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if entries.isEmpty {
                Text("No changed files in the working copy.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries, id: \.path, selection: $selectedPaths) { entry in
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 14)
                            .opacity(selectedPaths.contains(entry.path) ? 1 : 0)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.path)
                                .font(.system(size: 12.5, weight: .regular))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let sourcePath = entry.sourcePath {
                                Text("from \\(sourcePath)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(entry.statusLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedPaths.contains(entry.path) {
                            selectedPaths.remove(entry.path)
                        } else {
                            selectedPaths.insert(entry.path)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 160)
            }

            TextField("Commit message", text: $message, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Commit") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        selectedPaths.isEmpty
                            || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isCommitting
                    )
            }
        }
        .padding(20)
        .frame(width: 460, height: 380)
        .task {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let root = try? source.workspaceRoot() else {
            commitError = "Working copy is unavailable."
            return
        }
        let result = await Task.detached {
            GitClone.statusEntries(at: root)
        }.value
        entries = result
        // Nothing pre-selected: the user decides exactly what to stage.
        selectedPaths = []
    }

    private func commit() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedPaths.isEmpty, !trimmed.isEmpty, !isCommitting else { return }
        isCommitting = true
        commitError = nil
        let paths = Array(selectedPaths).sorted()
        Task {
            let result = await store.commitGithub(source.id, paths: paths, message: trimmed)
            isCommitting = false
            if result.isSuccess {
                onCommitted()
                dismiss()
            } else {
                commitError = Self.describe(result)
            }
        }
    }

    /// Git's exit + stderr verbatim; a repo-config hint when the failure
    /// is a missing identity — never a synthesized one.
    static func describe(_ result: GithubCommit.CommitResult) -> String {
        var text = "git commit failed (exit \(result.exitCode)): \(result.stderr)"
        if result.stderr.contains("user.email") || result.stderr.contains("user.name") {
            text += "\n\nSet user.name and user.email for this repository (git config user.name \"…\"; git config user.email …) — Solipsist never invents an identity."
        }
        return text
    }
}

/// New Pull Request sheet (M16-3 / #185): title + body over the
/// current branch, base defaulting to the source's `defaultBranch`
/// (from the remote, never guessed). When the branch has no upstream
/// it is pushed first (`-u`, M16-2's one-shot) so the PR has a branch
/// to point at; then `POST /repos/{owner}/{repo}/pulls` with the
/// Keychain bearer. Success opens the PR in the browser.
private struct PullRequestSheet: View {
    let source: GithubSource
    /// Runs after a successful PR (branchStatus refresh).
    let onCreated: () -> Void

    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var base = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var branch: String?
    @State private var hasUpstream = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Pull Request")
                .font(.headline)

            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            LabeledContent("Branch") {
                Text(branch ?? "—")
                    .monospaced()
            }
            LabeledContent("Base") {
                TextField("base branch", text: $base)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
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
                    Text(hasUpstream ? "Creating…" : "Pushing branch, then creating…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(hasUpstream ? "Create Pull Request" : "Push & Create Pull Request") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isWorking
                        || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || branch == nil
                        || base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(20)
        .frame(width: 480, height: 340)
        .task {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let root = try? source.workspaceRoot() else {
            errorText = "Working copy is unavailable."
            return
        }
        let result = await Task.detached {
            GitClone.branchStatus(at: root)
        }.value
        branch = result.branch
        hasUpstream = result.upstream != nil
        // Base = the source's defaultBranch (from the remote, never
        // guessed); the user may override it.
        base = source.defaultBranch
    }

    private func create() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let branch, !trimmedTitle.isEmpty, !trimmedBase.isEmpty, !isWorking else { return }
        isWorking = true
        errorText = nil
        Task {
            // Push the branch first when it has no upstream — the PR
            // needs a remote branch to point at. Reuses the M16-2
            // one-shot; auth rides the credential helper.
            if !hasUpstream {
                let pushResult = await store.pushGithub(source.id)
                guard pushResult.isSuccess else {
                    isWorking = false
                    errorText = RemoteMailboxView.describePush(pushResult)
                    return
                }
            }

            // Load the token from the Keychain (zero-leak: SecureBuffer,
            // never argv/env/logs) and create the PR over the transport.
            let tokenStore = GithubTokenStore()
            let transport = URLSessionGithubTransport()
            do {
                guard let token = try tokenStore.load() else {
                    throw GithubOAuthError.httpStatus(401, message: "No GitHub token in the Keychain. Re-authenticate from Settings → Sources.")
                }
                defer { token.wipe() }
                let created = try await GithubAPIClient.createPullRequest(
                    owner: source.owner,
                    repository: source.repository,
                    title: trimmedTitle,
                    body: bodyText,
                    head: branch,
                    base: trimmedBase,
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
                errorText = Self.describe(error)
            }
        }
    }

    static func describe(_ error: Error) -> String {
        if let github = error as? GithubOAuthError {
            switch github {
            case let .httpStatus(status, message):
                return "GitHub returned \(status): \(message)"
            case .invalidResponse:
                return "GitHub returned an unexpected response."
            case let .deviceCodeFailed(code, message):
                return "\(code): \(message)"
            }
        }
        return String(describing: error)
    }
}
