import SwiftUI

/// The M15 "Add GitHub Account…" sheet: device-flow OAuth with browser
/// confirm, PAT fallback, repo resolution, clone, Keychain, add.
struct AddGithubAccountSheet: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var flow = AddGithubFlowModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Add GitHub Account", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)
            content
            if let error = flow.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: flow.step) { _, step in
            if case .done = step {
                dismiss()
            }
        }
        .onDisappear {
            flow.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch flow.step {
        case .chooseMethod:
            chooseMethod
        case .awaitingAuthorization(let userCode):
            awaitingAuthorization(userCode: userCode)
        case .tokenInput:
            tokenInput
        case .repo(let identity):
            repoStep(identity: identity)
        case .cloning(let owner, let repository):
            cloning(owner: owner, repository: repository)
        case .done:
            EmptyView()
        }
    }

    private var chooseMethod: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in through your browser — GitHub shows a code, you confirm it here or on any device.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                flow.startDeviceFlow()
            } label: {
                Label("Sign in with GitHub", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(flow.isBusy)

            HStack {
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                Text("or")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            }

            Text("Use a fine-grained personal access token (the app-password path). No browser needed.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                flow.chooseTokenInput()
            } label: {
                Label("Use a token", systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(flow.isBusy)
        }
    }

    private func awaitingAuthorization(userCode: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub is waiting for you to authorize Solipsist.")
                .font(.callout)
            HStack(spacing: 10) {
                Text("Code:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(userCode)
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .textSelection(.enabled)
                Spacer()
            }
            Button("Open GitHub") {
                flow.reopenAuthorization()
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to confirm…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tokenInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste a GitHub personal access token. It is saved to the Keychain and used for clone and sync.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField("github_pat_…", text: $flow.tokenText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    flow.useToken()
                }
            Button("Verify") {
                flow.useToken()
            }
            .disabled(flow.isBusy)
        }
    }

    private func repoStep(identity: AddGithubFlowModel.GithubIdentity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signed in as \(identity.login)\(identity.name.map { " (\($0))" } ?? "")")
                .font(.callout)
            if !identity.scopes.isEmpty {
                Text("Granted scopes: \(identity.scopes.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("owner", text: $flow.ownerText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Text("/")
                    .foregroundStyle(.secondary)
                TextField("repository", text: $flow.repositoryText)
                    .textFieldStyle(.roundedBorder)
                Button("Check") {
                    flow.resolveRepository()
                }
                .disabled(flow.isBusy)
            }
            if let info = flow.repositoryInfo {
                Label(
                    "\(info.fullName) — default branch \(info.defaultBranch)\(info.isPrivate ? ", private" : "")",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.green)
            }
            Button {
                flow.cloneAndAdd(store: store)
            } label: {
                Label("Clone & Add", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(flow.isBusy || flow.repositoryInfo == nil)
        }
    }

    private func cloning(owner: String, repository: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Cloning \(owner)/\(repository)…")
                .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if case .done = flow.step {
                EmptyView()
            } else {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}
