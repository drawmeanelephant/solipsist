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

            Button("Clone Repository…") {
                store.presentClonePanel()
            }

            Button("New Draft with Apple Intelligence…") {
                PostDraftPrompt.runAndStage()
            }

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

            Divider()

            Button("Edit Page") {
                openWindow(id: CompanionID.editor)
            }
            .disabled(!store.selection.canEditPage)
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

            Button("Export Source RAG…") {
                runtime.coordinator.run(.sourceRag, store: store, runtime: runtime)
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

        /// #264: reading comfort for the compose buffer — type ladder and
        /// gutter toggle, persisted as machine state (UserDefaults).
        CommandGroup(after: .textFormatting) {
            Button("Zoom In") {
                runtime.composeTypography.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom Out") {
                runtime.composeTypography.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                runtime.composeTypography.resetToActualSize()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Toggle("Line Numbers", isOn: Binding(
                get: { runtime.composeTypography.showsLineNumbers },
                set: { runtime.composeTypography.setLineNumbers($0) }
            ))
        }

        /// #276: sidebar navigation verbs — mailbox jumps for the selected
        /// source and next/previous source cycling.
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Pages") {
                store.select(mailbox: WorkspaceMailbox.pages)
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(!hasSource)

            Button("Outputs") {
                store.select(mailbox: WorkspaceMailbox.outputs)
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(!hasSource)

            Button("Publish") {
                store.select(mailbox: WorkspaceMailbox.publish)
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(!hasSource)

            Button("Plan") {
                store.select(mailbox: WorkspaceMailbox.plan)
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(!hasSource)

            Button("Activity") {
                store.select(mailbox: WorkspaceMailbox.activity)
            }
            .keyboardShortcut("5", modifiers: .command)
            .disabled(!hasSource)

            Button("Content Audit") {
                store.select(mailbox: WorkspaceMailbox.contentAudit)
            }
            .keyboardShortcut("6", modifiers: .command)
            .disabled(!hasSource)

            Divider()

            Button("Select Next Source") {
                cycleSource(forward: true)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(store.sources.count < 2)

            Button("Select Previous Source") {
                cycleSource(forward: false)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(store.sources.count < 2)
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

    /// #276: walk the sidebar's source order one step, wrapping.
    private func cycleSource(forward: Bool) {
        let next = SidebarNavigation.cycledSource(
            current: store.selection.sourceID,
            ids: store.sourceIDs,
            forward: forward
        )
        guard let next else { return }
        store.select(next)
    }
}
