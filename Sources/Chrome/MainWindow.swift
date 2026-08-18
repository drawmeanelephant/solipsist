import SwiftUI

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
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            PlayHost()
        }
        .navigationTitle("Solipsist")
        .inspector(isPresented: $inspectorPresented) {
            InspectorDrawer()
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 380)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    runtime.coordinator.run(.validate, store: store, runtime: runtime)
                } label: {
                    Label("Validate", systemImage: "checkmark.circle")
                }
                .help("Validate")
                .disabled(store.selectedSource == nil || !runtime.coordinator.canRunVerb)

                Button {
                    runtime.coordinator.run(.buildIR, store: store, runtime: runtime)
                } label: {
                    Label("Build IR", systemImage: "hammer")
                }
                .help("Build IR")
                .disabled(store.selectedSource == nil || !runtime.coordinator.canRunVerb)

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
                .disabled(store.selectedSource == nil)

                Button {
                    openWindow(id: CompanionID.editor)
                } label: {
                    Label("Editor", systemImage: "square.and.pencil")
                }
                .help("Open Editor")
                .disabled(store.selectedSource == nil)
            }
        }
        .onAppear {
            runtime.coordinator.syncSaveWatch(store: store, runtime: runtime)
        }
        .onChange(of: store.selection.sourceID) {
            runtime.coordinator.syncSaveWatch(store: store, runtime: runtime)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
        .alert("Workspace", isPresented: errorPresented) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .frame(minWidth: 800, minHeight: 480)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let source = store.selectedSource {
                Image(systemName: source.symbolName)
                Text(source.title)
                if let detail = source.detailLine {
                    Text("·")
                    Text(detail)
                        .truncationMode(.middle)
                }
            } else {
                Text("No source")
            }
            Spacer()
            Text(runtime.statusLine)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }
}
