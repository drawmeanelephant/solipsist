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

    var body: some View {
        List {
            syncSection
            commitSection
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
