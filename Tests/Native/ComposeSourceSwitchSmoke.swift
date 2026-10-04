import AppKit
@testable import Solipsist
import SwiftUI

/// Run against a Debug app build on macOS 27. Uses only temporary content
/// and an isolated defaults suite, never the user's workspace inventory.
@main
@MainActor
enum ComposeSourceSwitchSmoke {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    private struct Publication {
        let root: URL
        let id: SourceID
    }

    private static func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("compose-native-\(UUID())")
        let suite = "dev.drawmeanelephant.compose-smoke.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let first = try makePublication(root: root.appendingPathComponent("A"), text: "Publication A")
        let second = try makePublication(root: root.appendingPathComponent("B"), text: "Publication B")
        let invocations = root.appendingPathComponent("validation.txt")
        try makeEngineStub(root: root, invocations: invocations)
        let store = WorkspaceStore(defaults: defaults)
        let runtime = AppRuntime()
        try check(runtime.enginePath == root.appendingPathComponent("boris-stub").path, "the smoke did not select its stub engine")
        store.addLocal(url: first)
        let firstID = try require(store.selectedSource?.id, "first source")
        store.addLocal(url: second)
        let secondID = try require(store.selectedSource?.id, "second source")
        let noun = WorkspaceNoun(kind: "page", id: "index", title: "Index", sourcePath: "index.md")
        store.select(firstID)
        store.select(noun: noun)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Compose source-switch smoke"
        window.contentView = NSHostingView(rootView: ComposeWindow().environment(store).environment(runtime))
        window.makeKeyAndOrderFront(nil)
        app.activate()
        defer {
            window.close()
            runtime.coordinator.terminateAll(runtime: runtime)
        }

        try checkSwitches(
            store: store, window: window,
            first: Publication(root: first, id: firstID),
            second: Publication(root: second, id: secondID),
            noun: noun
        )
        try checkValidation(store: store, runtime: runtime, sourceID: firstID, invocations: invocations)
        try checkGithub(store: store, runtime: runtime, window: window, root: root, invocations: invocations)
    }

    private static func makeEngineStub(root: URL, invocations: URL) throws {
        let binary = root.appendingPathComponent("boris-stub")
        let script = """
        #!/bin/sh
        if [ "$1" != "--version" ]; then
          printf 'CALL\\n%s\\n' "$PWD" >> "$COMPOSE_SMOKE_INVOCATIONS"
          printf '%s\\n' "$@" >> "$COMPOSE_SMOKE_INVOCATIONS"
          printf 'END\\n' >> "$COMPOSE_SMOKE_INVOCATIONS"
        fi
        if [ -f fail-command ]; then echo 'working-copy failure' >&2; exit 3; fi
        case "$1" in
          --version) printf 'boris/0.8.1\\n' ;;
          validate) ;;
          plan) cat "$COMPOSE_SMOKE_FIXTURES/plan-happy/plan.json" ;;
          --out) cp "$COMPOSE_SMOKE_FIXTURES/happy-ir/build-report.json" "$2/build-report.json" ;;
          *) exit 2 ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        setenv("SOLIPSIST_BORIS_BIN", binary.path, 1)
        setenv("COMPOSE_SMOKE_INVOCATIONS", invocations.path, 1)
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        setenv("COMPOSE_SMOKE_FIXTURES", fixtures.path, 1)
    }

    private static func checkValidation(store: WorkspaceStore, runtime: AppRuntime, sourceID: SourceID, invocations: URL) throws {
        guard let item = store.sources.first(where: { $0.id == sourceID }) else {
            throw SmokeFailure(message: "missing validation owner")
        }
        let owner = try ComposeSourceBinding(source: item.folderSource)
        try "".write(to: invocations, atomically: true, encoding: .utf8)
        runtime.coordinator.syncSaveWatch(store: store, runtime: runtime)
        runtime.coordinator.noteSave(source: owner)
        try wait("source-bound validation despite selected B") {
            guard let text = try? String(contentsOf: invocations, encoding: .utf8) else { return false }
            let lines = text.components(separatedBy: "\n")
            let cwd = lines.dropFirst().first.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            return cwd == owner.workspaceRoot.resolvingSymlinksInPath() && lines.contains(owner.contentRoot.path) && lines.contains("validate")
        }
        print("PASS delayed validation uses the \(item.kind) owner's roots with another source selected")
    }
}

extension ComposeSourceSwitchSmoke {
    private static func checkGithub(
        store: WorkspaceStore, runtime: AppRuntime, window: NSWindow, root: URL, invocations: URL
    ) throws {
        try wait("previous validation finished") { !runtime.coordinator.isRunning }
        guard let local = store.sources.first(where: { $0.kind == .local }) else {
            throw SmokeFailure(message: "missing local source")
        }
        try checkCommands(store: store, runtime: runtime, source: local, invocations: invocations)
        let folder = try makePublication(root: root.appendingPathComponent("Github"), text: "GitHub page")
        let github = try require(store.addGithub(
            workingCopy: folder, owner: "example", repository: "publication", defaultBranch: "main", grantedScopes: []
        ), "GitHub working copy")
        let noun = WorkspaceNoun(kind: "page", id: "index", title: "Index", sourcePath: "index.md")
        store.select(noun: noun)
        try wait("GitHub Compose loads") { editor(in: window)?.string == "GitHub page" }
        try checkCommands(store: store, runtime: runtime, source: .github(github), invocations: invocations)
        let readyAt = Date().addingTimeInterval(2.1)
        try wait("manual validation freshness expires") { Date() >= readyAt }
        try edit("Saved GitHub page", in: window)
        store.select(local.id)
        store.select(noun: noun)
        try clickDialog("Cancel", in: window)
        try wait("GitHub cancel restores owner") { store.selection.sourceID == github.id && editor(in: window)?.string == "Saved GitHub page" }
        store.select(local.id)
        store.select(noun: noun)
        try clickDialog("Save Changes", in: window)
        try wait("GitHub Save writes its own file") {
            (try? String(contentsOf: folder.appendingPathComponent("content/index.md"), encoding: .utf8)) == "Saved GitHub page"
        }
        try wait("GitHub save validation finished") { !runtime.coordinator.isRunning }
        try checkValidation(store: store, runtime: runtime, sourceID: github.id, invocations: invocations)
        try wait("GitHub bound validation finished") { !runtime.coordinator.isRunning }
        try checkFailures(store: store, runtime: runtime, source: github)
        print("PASS GitHub Compose, Cancel/Save, manual commands, bound validation, and failure diagnostics")
    }

    private static func checkCommands(store: WorkspaceStore, runtime: AppRuntime, source: SourceItem, invocations: URL) throws {
        store.select(source.id)
        let folder = source.folderSource
        for verb in [CoordinatorVerb.plan, .validate, .buildIR] {
            try "".write(to: invocations, atomically: true, encoding: .utf8)
            runtime.coordinator.run(verb, store: store, runtime: runtime)
            try wait("\(source.kind) \(verb)") { !runtime.coordinator.isRunning }
            try check(runtime.coordinator.exitCode == 0, "\(source.kind) \(verb) failed: \(runtime.coordinator.summary)")
            let text = try String(contentsOf: invocations, encoding: .utf8)
            let root = try folder.workspaceRoot()
            try check(text.contains(root.resolvingSymlinksInPath().path), "command ran outside its source workspace")
            if verb == .plan {
                try check(text.contains("--profile\nboris.json"), "Plan did not use the source profile")
            } else {
                try check(text.contains(try folder.contentRoot().path), "command did not use the source content root")
            }
            if verb == .buildIR {
                try check(text.contains("--out\n.boris"), "Build did not keep its output workspace-relative")
            }
            try check(!text.contains("standard-site") && !text.contains("nostr") && !text.contains("push"), "local operation invoked publication")
        }
        print("PASS \(source.kind) Plan/Validate/Build use source-bound roots and relative outputs")
    }

    private static func checkFailures(store: WorkspaceStore, runtime: AppRuntime, source: GithubSource) throws {
        store.select(source.id)
        let root = try source.workspaceRoot()
        let marker = root.appendingPathComponent("fail-command")
        try "".write(to: marker, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: marker) }
        runtime.coordinator.run(.validate, store: store, runtime: runtime)
        try wait("failed GitHub command finished") { !runtime.coordinator.isRunning }
        try check(runtime.coordinator.exitCode == 3, "nonzero working-copy exit was lost")
        try check(runtime.coordinator.problems.contains { $0.message.contains("working-copy failure") }, "working-copy stderr was lost")
        try FileManager.default.removeItem(at: marker)
        try FileManager.default.removeItem(at: root)
        runtime.coordinator.run(.validate, store: store, runtime: runtime)
        try check(runtime.coordinator.problems.contains { $0.code == "source" }, "missing working folder was not explained")
        try check(runtime.coordinator.summary.contains("working folder"), "missing folder message was not actionable")
    }
}

extension ComposeSourceSwitchSmoke {
    private static func checkSwitches(
        store: WorkspaceStore, window: NSWindow, first: Publication, second: Publication, noun: WorkspaceNoun
    ) throws {
        try wait("load A") { editor(in: window)?.string == "Publication A" }
        store.select(second.id)
        store.select(noun: noun)
        try wait("equal noun loads B") { editor(in: window)?.string == "Publication B" }
        print("PASS native clean source switch with equal nouns")

        store.select(first.id)
        store.select(noun: noun)
        try wait("return to A") { editor(in: window)?.string == "Publication A" }
        try edit("Unsaved A", in: window)
        store.select(second.id)
        store.select(noun: noun)
        try clickDialog("Cancel", in: window)
        try wait("cancel restores source A") { store.selection.sourceID == first.id && editor(in: window)?.string == "Unsaved A" }
        print("PASS native dirty Cancel preserves A and restores source identity")

        store.select(second.id)
        store.select(noun: noun)
        try clickDialog("Discard Changes", in: window)
        try wait("discard loads B") { editor(in: window)?.string == "Publication B" }
        try check(try String(contentsOf: first.root.appendingPathComponent("content/index.md"), encoding: .utf8) == "Publication A", "discard wrote A")
        print("PASS native dirty Discard switches without writing")

        store.select(first.id)
        store.select(noun: noun)
        try wait("load A for save") { editor(in: window)?.string == "Publication A" }
        try edit("Saved A", in: window)
        store.select(second.id)
        store.select(noun: noun)
        try clickDialog("Save Changes", in: window)
        try wait("save then switch to B") { editor(in: window)?.string == "Publication B" }
        try check(try String(contentsOf: first.root.appendingPathComponent("content/index.md"), encoding: .utf8) == "Saved A", "Save did not write A")
        try check(try String(contentsOf: second.root.appendingPathComponent("content/index.md"), encoding: .utf8) == "Publication B", "Save overwrote B")
        print("PASS native dirty Save writes A before loading B")
    }

    private static func makePublication(root: URL, text: String) throws -> URL {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("content"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".boris"), withIntermediateDirectories: true)
        try "{}".write(to: root.appendingPathComponent("boris.json"), atomically: true, encoding: .utf8)
        try text.write(to: root.appendingPathComponent("content/index.md"), atomically: true, encoding: .utf8)
        let graph = """
        {"schemaVersion":"ir-graph-0.3.0","frozen":true,"nodes":[
        {"index":0,"id":"index","sourcePath":"index.md","role":"trunk","parent":null,
        "parentIndex":null,"title":"Index","status":null,"tags":[],"bodyOffset":null}
        ],"edges":[],"reverseIndex":[],"nav":[]}
        """
        try graph.write(to: ComposePageResolver.graphURL(workspaceRoot: root), atomically: true, encoding: .utf8)
        return root
    }

    private static func editor(in window: NSWindow) -> NSTextView? {
        guard let root = window.contentView else { return nil }
        return descendants(root).compactMap { $0 as? NSTextView }.first { $0.isEditable }
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private static func edit(_ text: String, in window: NSWindow) throws {
        let textView = try require(editor(in: window), "native text view")
        let range = NSRange(location: 0, length: (textView.string as NSString).length)
        if textView.shouldChangeText(in: range, replacementString: text) {
            textView.textStorage?.replaceCharacters(in: range, with: text)
            textView.didChangeText()
        }
    }

    private static func clickDialog(_ title: String, in window: NSWindow) throws {
        var button: NSButton?
        try wait("dialog button \(title)") {
            button = window.sheets.filter(\.isVisible).compactMap(\.contentView).flatMap(descendants)
                .compactMap { $0 as? NSButton }.first { $0.title == title }
            return button != nil
        }
        button?.performClick(nil)
        try wait("dialog dismissed") { window.sheets.isEmpty }
    }

    private static func wait(_ name: String, until predicate: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate(), Date() < deadline {
            while let event = NSApplication.shared.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                NSApplication.shared.sendEvent(event)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try check(predicate(), "timed out: \(name)")
    }

    private static func require<T>(_ value: T?, _ name: String) throws -> T {
        guard let value else { throw SmokeFailure(message: "missing \(name)") }
        return value
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw SmokeFailure(message: message) }
    }

    private struct SmokeFailure: Error {
        let message: String
    }
}
