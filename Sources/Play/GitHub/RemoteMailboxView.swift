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

    var body: some View {
        List {
            syncSection
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
