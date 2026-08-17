import SwiftUI

/// Menu bar. If it is not here, it is not a feature.
struct SolipsistCommands: Commands {
    @Bindable var store: WorkspaceStore
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
}
