import SwiftUI

/// Menu bar. If it is not here, it is not a feature.
struct SolipsistCommands: Commands {
    @Bindable var store: WorkspaceStore
    var runtime: AppRuntime
    @Binding var inspectorPresented: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") {
                store.presentOpenPanel()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Remove Source") {
                if let id = store.selection.sourceID {
                    store.remove(id)
                }
            }
            .disabled(store.selection.sourceID == nil)
        }

        CommandMenu("Boris") {
            Button("Plan") {
                runtime.coordinator.run(.plan, store: store, runtime: runtime)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(!hasSource || runtime.coordinator.isRunning)

            Button("Validate") {
                runtime.coordinator.run(.validate, store: store, runtime: runtime)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(!hasSource || runtime.coordinator.isRunning)

            Button("Build IR") {
                runtime.coordinator.run(.buildIR, store: store, runtime: runtime)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(!hasSource || runtime.coordinator.isRunning)

            Button("Build HTML") {
                runtime.coordinator.run(.buildHTML, store: store, runtime: runtime)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(!hasSource || runtime.coordinator.isRunning)

            Divider()

            Button("Check") {
                runtime.coordinator.run(.check, store: store, runtime: runtime)
            }
            .disabled(!hasSource || runtime.coordinator.isRunning)

            Button("Impact") {
                runtime.coordinator.run(.impact, store: store, runtime: runtime)
            }
            .disabled(!hasPage || runtime.coordinator.isRunning)

            Divider()

            Button("Stop") {
                runtime.coordinator.stop(runtime: runtime)
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!runtime.coordinator.isRunning)
        }

        CommandGroup(after: .sidebar) {
            Button(inspectorPresented ? "Hide Inspector" : "Show Inspector") {
                inspectorPresented.toggle()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])

            Divider()

            Button("Preview") {
                openWindow(id: CompanionID.preview)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Editor") {
                openWindow(id: CompanionID.editor)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }

    private var hasSource: Bool { store.selectedSource != nil }

    private var hasPage: Bool { store.selection.noun?.kind == "page" }
}
