import SwiftUI

@main
struct SolipsistApp: App {
    @State private var store = WorkspaceStore()
    @State private var runtime = AppRuntime()
    @State private var inspectorPresented = true

    var body: some Scene {
        WindowGroup {
            MainWindow(inspectorPresented: $inspectorPresented)
                .environment(store)
                .environment(runtime)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            SolipsistCommands(
                store: store,
                runtime: runtime,
                inspectorPresented: $inspectorPresented
            )
        }

        WindowGroup("Preview", id: CompanionID.preview) {
            PreviewWindow()
                .environment(store)
                .environment(runtime)
        }
        .defaultSize(width: 720, height: 560)

        WindowGroup("Editor", id: CompanionID.editor) {
            EditorWindow()
                .environment(store)
                .environment(runtime)
        }
        .defaultSize(width: 720, height: 560)
    }
}
