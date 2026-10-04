import AppKit
import SwiftUI

/// Close and Quit share the same explicit Save / Don't Save / Cancel gate.
/// Weak registration keeps closed Compose windows out of the Quit review.
@MainActor
final class ComposeWindowRegistry {
    static let shared = ComposeWindowRegistry()
    private let guardians = NSHashTable<ComposeWindowGuardian>.weakObjects()

    func register(_ guardian: ComposeWindowGuardian) {
        guardians.add(guardian)
    }

    func unregister(_ guardian: ComposeWindowGuardian) {
        guardians.remove(guardian)
    }

    func canTerminate() -> Bool {
        guardians.allObjects.allSatisfy { $0.reviewUnsavedChanges() }
    }
}

/// A delegate proxy, not a replacement for SwiftUI's window bookkeeping.
@MainActor
final class ComposeWindowGuardian: NSObject, NSWindowDelegate {
    enum Decision {
        case save
        case discard
        case cancel
    }

    typealias Confirm = @MainActor (NSWindow, String) -> Decision

    private let registry: ComposeWindowRegistry
    private let confirm: Confirm
    private weak var window: NSWindow?
    private weak var previousDelegate: (any NSWindowDelegate)?
    private var document: ComposeDocument?
    private var save: (() -> Bool)?

    init(
        registry: ComposeWindowRegistry = .shared,
        confirm: @escaping Confirm = ComposeWindowGuardian.confirmClose
    ) {
        self.registry = registry
        self.confirm = confirm
        super.init()
    }

    func configure(document: ComposeDocument, save: @escaping () -> Bool) {
        self.document = document
        self.save = save
        window?.isDocumentEdited = document.isDirty
    }

    func attach(to window: NSWindow?) {
        guard self.window !== window else { return }
        detach()
        guard let window else { return }
        self.window = window
        previousDelegate = window.delegate
        window.delegate = self
        window.isDocumentEdited = document?.isDirty == true
        registry.register(self)
    }

    func detach() {
        if let window, window.delegate === self {
            window.delegate = previousDelegate
        }
        registry.unregister(self)
        window = nil
        previousDelegate = nil
    }

    func reviewUnsavedChanges() -> Bool {
        guard let document, document.isDirty else { return true }
        guard let window else { return false }
        switch confirm(window, document.fileURL?.lastPathComponent ?? "Untitled") {
        case .save:
            return save?() == true && !document.isDirty
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard previousDelegate?.windowShouldClose?(sender) != false else { return false }
        return reviewUnsavedChanges()
    }

    override nonisolated func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        return MainActor.assumeIsolated { previousDelegate?.responds(to: selector) == true }
    }

    override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
        // AppKit queries its delegate synchronously on the main thread.
        // Keep that guarantee checked at the Objective-C bridge.
        let target = MainActor.assumeIsolated {
            DelegateTarget(value: previousDelegate?.responds(to: selector) == true ? previousDelegate : nil)
        }
        return target.value ?? super.forwardingTarget(for: selector)
    }

    /// Only passes the delegate back to AppKit on that same checked thread.
    private struct DelegateTarget: @unchecked Sendable {
        let value: (any NSWindowDelegate)?
    }

    private static func confirmClose(_ window: NSWindow, _ name: String) -> Decision {
        window.makeKeyAndOrderFront(nil)
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to “\(name)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        alert.buttons[1].keyEquivalent = "\u{1B}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }
}

/// The AppKit window exists only after the SwiftUI view is mounted.
struct ComposeWindowLifecycle: NSViewRepresentable {
    let document: ComposeDocument
    let isDirty: Bool
    let onSave: () -> Bool

    func makeCoordinator() -> ComposeWindowGuardian {
        ComposeWindowGuardian()
    }

    func makeNSView(context: Context) -> WindowProbe {
        let probe = WindowProbe()
        probe.guardian = context.coordinator
        context.coordinator.configure(document: document, save: onSave)
        return probe
    }

    func updateNSView(_ probe: WindowProbe, context: Context) {
        context.coordinator.configure(document: document, save: onSave)
        context.coordinator.attach(to: probe.window)
    }

    static func dismantleNSView(_ probe: WindowProbe, coordinator: ComposeWindowGuardian) {
        coordinator.detach()
    }

    final class WindowProbe: NSView {
        weak var guardian: ComposeWindowGuardian?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guardian?.attach(to: window)
        }
    }
}
