import SwiftUI
import UniformTypeIdentifiers

/// The one window: sources | play | inspector drawer.
///
/// The trailing column is `.inspector` (not NavigationSplitView's detail
/// column) so it collapses like a drawer — Mail / Finder / Xcode. Preview
/// and the editor are companion windows, not columns.
struct MainWindow: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow
    @Binding var inspectorPresented: Bool

    var body: some View {
        NavigationSplitView {
            SourceSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            PlayHost()
        }
        .glassEffect()
        .navigationTitle("Solipsist")
        .inspector(isPresented: $inspectorPresented) {
            InspectorDrawer()
                .inspectorColumnWidth(min: 280, ideal: 330, max: 440)
        }
        .inspectorColumnWidth(min: 280, ideal: 330, max: 440)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                mainToolbar
            }
        }
        .onAppear {
            runtime.coordinator.syncSaveWatch(store: store, runtime: runtime)
            runtime.coordinator.syncValidateWatch(store: store, runtime: runtime)
        }
        .onChange(of: store.selection.sourceID) {
            runtime.coordinator.syncSaveWatch(store: store, runtime: runtime)
            runtime.coordinator.syncValidateWatch(store: store, runtime: runtime)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            var handled = false
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in
                            store.openFromSystem(url)
                        }
                    }
                    handled = true
                }
            }
            return handled
        }
        .alert("Workspace", isPresented: errorPresented) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .frame(minWidth: 920, minHeight: 520)
    }

    @ViewBuilder
    private var mainToolbar: some View {
        let hasSource = store.selectedSource != nil
        let canRun = hasSource && runtime.coordinator.canRunVerb
        let canEdit = store.selection.canEditPage
        let hasPage = store.selection.noun?.kind == "page"

        Button {
            runtime.coordinator.run(.plan, store: store, runtime: runtime)
        } label: {
            Label("Plan", systemImage: "doc.plaintext")
        }
        .help("Plan")
        .disabled(!canRun)

        Button {
            runtime.coordinator.run(.validate, store: store, runtime: runtime)
        } label: {
            Label("Validate", systemImage: "checkmark.circle")
        }
        .help("Validate")
        .disabled(!canRun)

        Button {
            runtime.coordinator.run(.buildIR, store: store, runtime: runtime)
        } label: {
            Label("Build IR", systemImage: "hammer")
        }
        .help("Build IR")
        .disabled(!canRun)

        Button {
            runtime.coordinator.run(.buildAll, store: store, runtime: runtime)
        } label: {
            Label("Build All", systemImage: "hammer.fill")
        }
        .help("Build All")
        .disabled(!canRun)

        Menu {
            Button {
                runtime.coordinator.run(.check, store: store, runtime: runtime)
            } label: {
                Text("Check")
            }
            .disabled(!canRun)

            Button {
                runtime.coordinator.run(.impact, store: store, runtime: runtime)
            } label: {
                Text("Impact")
            }
            .disabled(!hasPage || !runtime.coordinator.canRunVerb)
        } label: {
            Label("Boris…", systemImage: "ellipsis.circle")
        }
        .help("Boris…")

        Button {
            runtime.coordinator.stop(runtime: runtime)
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .help("Stop")
        .disabled(!runtime.coordinator.canStop)

        Button {
            openWindow(id: CompanionID.preview)
        } label: {
            Label("Preview", systemImage: "safari")
        }
        .help("Open Preview")
        .disabled(!hasSource)

        Button {
            openWindow(id: CompanionID.editor)
        } label: {
            Label("Editor", systemImage: "square.and.pencil")
        }
        .help("Open Editor")
        .disabled(!canEdit)

        Button {
            openWindow(id: CompanionID.compose)
        } label: {
            Label("Compose", systemImage: "pencil")
        }
        .help("Compose")
        .disabled(!canEdit)

        Button {
            inspectorPresented.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
        }
        .help("Toggle Inspector (⌥⌘0)")
    }

    private var statusBar: some View {
        let sourceTitle = store.selectedSource?.title ?? "No source"
        let verbText = runtime.statusVerbText
        let exitText = runtime.statusExitText
        let isFailure = runtime.statusExitIsFailure
        return HStack(spacing: 6) {
            Text(sourceTitle)
            Text("·")
            Text(verbText)
            Text("·")
            Text(exitText)
                .foregroundStyle(isFailure ? Color.red : Color.secondary)
            Text("·")
            Text(runtime.engineVersion)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .help(runtime.statusTooltip ?? "")
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }
}
