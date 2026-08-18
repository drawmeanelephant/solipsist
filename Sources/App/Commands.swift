import SwiftUI

/// Menu bar. If it is not here, it is not a feature.
struct SolipsistCommands: Commands {
    @Bindable var store: WorkspaceStore
    var runtime: AppRuntime
    @Binding var inspectorPresented: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                store.presentNewProjectPanel(runtime: runtime)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open…") {
                store.presentOpenPanel()
            }
            .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent") {
                if store.recentFolderURLs.isEmpty {
                    Button("No Recent Folders") {}
                        .disabled(true)
                } else {
                    ForEach(store.recentFolderURLs, id: \.path) { url in
                        Button(recentTitle(url)) {
                            store.addLocal(url: url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        store.clearRecentFolders()
                    }
                }
            }

            Button("Relocate Source…") {
                if let id = store.selection.sourceID {
                    store.presentRelocatePanel(for: id)
                }
            }
            .disabled(store.selectedSource?.isAvailable != false)

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
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Validate") {
                runtime.coordinator.run(.validate, store: store, runtime: runtime)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Build IR") {
                runtime.coordinator.run(.buildIR, store: store, runtime: runtime)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Build HTML") {
                runtime.coordinator.run(.buildHTML, store: store, runtime: runtime)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Build All") {
                runtime.coordinator.run(.buildAll, store: store, runtime: runtime)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Build This") {
                runtime.coordinator.run(.buildThis, store: store, runtime: runtime)
            }
            .disabled(!hasOutput || !runtime.coordinator.canRunVerb)

            Divider()

            Button("Check") {
                runtime.coordinator.run(.check, store: store, runtime: runtime)
            }
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Impact") {
                runtime.coordinator.run(.impact, store: store, runtime: runtime)
            }
            .disabled(!hasPage || !runtime.coordinator.canRunVerb)

            Button("Recipe Scale") {
                runtime.coordinator.run(.recipeScale, store: store, runtime: runtime)
            }
            .disabled(!hasPage || !runtime.coordinator.canRunVerb)

            Divider()

            Button("Publish to Standard.site") {
                runtime.coordinator.run(.publishStandardSite, store: store, runtime: runtime)
            }
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Verify Standard.site") {
                runtime.coordinator.run(.standardSiteVerify, store: store, runtime: runtime)
            }
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Standard.site Records") {
                runtime.coordinator.run(.standardSiteRecords, store: store, runtime: runtime)
            }
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Standard.site Sessions") {
                runtime.coordinator.run(.standardSiteSessions, store: store, runtime: runtime)
            }
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Standard.site Smoke Test") {
                runtime.coordinator.run(.standardSiteSmoke, store: store, runtime: runtime)
            }
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Button("Logout Standard.site") {
                runtime.coordinator.run(.standardSiteLogout, store: store, runtime: runtime)
            }
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Divider()

            Button("Publish to Nostr…") {
                runtime.coordinator.run(.publishNostr, store: store, runtime: runtime)
            }
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Divider()

            Button("Package Archive") {
                runtime.coordinator.run(.package, store: store, runtime: runtime)
            }
            .disabled(!hasSource || !runtime.coordinator.canRunVerb)

            Divider()

            Button("Stop") {
                runtime.coordinator.stop(runtime: runtime)
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!runtime.coordinator.canStop)
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

            Button("Compose") {
                openWindow(id: CompanionID.compose)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Button("Solipsist Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }

    private func recentTitle(_ url: URL) -> String {
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent().path
        return parent.isEmpty ? name : "\(name) — \(parent)"
    }

    private var hasSource: Bool { store.selectedSource != nil }

    private var hasPage: Bool { store.selection.noun?.kind == "page" }

    private var hasOutput: Bool {
        let kind = store.selection.noun?.kind
        return kind == "target" || kind == "edition"
    }
}
