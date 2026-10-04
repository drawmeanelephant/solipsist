import AppKit
import XCTest

@MainActor
final class ComposeWindowLifecycleTests: XCTestCase {
    private func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    func testCleanWindowClosesWithoutPrompting() {
        let window = window()
        let guardian = ComposeWindowGuardian(registry: ComposeWindowRegistry()) { _, _ in
            XCTFail("a clean buffer needs no confirmation")
            return .cancel
        }
        guardian.configure(document: ComposeDocument(), save: { false })
        guardian.attach(to: window)
        defer { guardian.detach() }
        XCTAssertFalse(window.isDocumentEdited)
        XCTAssertTrue(guardian.windowShouldClose(window))
    }

    func testDirtyWindowCancelKeepsTheBufferOpen() {
        let window = window()
        let document = ComposeDocument(text: "Unsaved draft")
        let guardian = ComposeWindowGuardian(registry: ComposeWindowRegistry()) { _, name in
            XCTAssertEqual(name, "Untitled")
            return .cancel
        }
        guardian.configure(document: document, save: {
            XCTFail("Cancel must not save")
            return false
        })
        guardian.attach(to: window)
        defer { guardian.detach() }
        XCTAssertTrue(window.isDocumentEdited)
        XCTAssertFalse(guardian.windowShouldClose(window))
        XCTAssertEqual(document.text, "Unsaved draft")
        XCTAssertTrue(document.isDirty)
    }

    func testDiscardAllowsCloseWithoutWriting() {
        let window = window()
        let document = ComposeDocument(text: "Unsaved draft")
        let guardian = ComposeWindowGuardian(registry: ComposeWindowRegistry()) { _, _ in .discard }
        guardian.configure(document: document, save: {
            XCTFail("Discard must not save")
            return false
        })
        guardian.attach(to: window)
        defer { guardian.detach() }
        XCTAssertTrue(guardian.windowShouldClose(window))
        XCTAssertTrue(document.isDirty)
        XCTAssertNil(document.fileURL)
    }

    func testSaveCancellationOrFailureBlocksCloseAndQuit() {
        let window = window()
        let registry = ComposeWindowRegistry()
        let document = ComposeDocument(text: "Unsaved draft")
        var attempts = 0
        let guardian = ComposeWindowGuardian(registry: registry) { _, _ in .save }
        guardian.configure(document: document, save: {
            attempts += 1
            return false
        })
        guardian.attach(to: window)
        defer { guardian.detach() }
        XCTAssertFalse(guardian.windowShouldClose(window))
        XCTAssertFalse(registry.canTerminate())
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(document.isDirty)
    }

    func testSuccessfulExplicitSaveAllowsClose() throws {
        let window = window()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-close-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = ComposeDocument(text: "Unsaved draft")
        let guardian = ComposeWindowGuardian(registry: ComposeWindowRegistry()) { _, _ in .save }
        guardian.configure(document: document, save: {
            document.fileURL = url
            return (try? document.save()) == true
        })
        guardian.attach(to: window)
        defer { guardian.detach() }
        XCTAssertTrue(guardian.windowShouldClose(window))
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Unsaved draft")
    }

    func testQuitReviewsEveryWindowAndDetachedWindowsDoNotBlockIt() {
        let registry = ComposeWindowRegistry()
        let first = window()
        let second = window()
        let clean = ComposeWindowGuardian(registry: registry) { _, _ in
            XCTFail("clean window")
            return .cancel
        }
        let dirty = ComposeWindowGuardian(registry: registry) { _, _ in .cancel }
        clean.configure(document: ComposeDocument(), save: { false })
        dirty.configure(document: ComposeDocument(text: "Unsaved draft"), save: { false })
        clean.attach(to: first)
        dirty.attach(to: second)
        defer {
            clean.detach()
            dirty.detach()
        }
        XCTAssertFalse(registry.canTerminate())
        dirty.detach()
        XCTAssertTrue(registry.canTerminate())
    }

    func testPreviousDelegateIsPreservedAndCanVetoClose() {
        let window = window()
        let previous = VetoDelegate()
        window.delegate = previous
        let guardian = ComposeWindowGuardian(registry: ComposeWindowRegistry()) { _, _ in .discard }
        guardian.configure(document: ComposeDocument(text: "Unsaved"), save: { false })
        guardian.attach(to: window)
        XCTAssertTrue(window.delegate === guardian)
        XCTAssertFalse(guardian.windowShouldClose(window))
        XCTAssertEqual(previous.closeRequests, 1)
        window.delegate?.windowDidResize?(Notification(name: NSWindow.didResizeNotification, object: window))
        XCTAssertEqual(previous.resizeNotifications, 1, "SwiftUI's other delegate methods must still receive callbacks")
        guardian.detach()
        XCTAssertTrue(window.delegate === previous)
    }

    func testUndoRefreshesTheNativeEditedIndicator() {
        let window = window()
        let document = ComposeDocument(text: "", fileURL: URL(fileURLWithPath: "/test/note.md"))
        let guardian = ComposeWindowGuardian(registry: ComposeWindowRegistry()) { _, _ in .cancel }
        guardian.configure(document: document, save: { false })
        guardian.attach(to: window)
        defer { guardian.detach() }
        document.text = "Edit"
        guardian.configure(document: document, save: { false })
        XCTAssertTrue(window.isDocumentEdited)
        document.text = ""
        guardian.configure(document: document, save: { false })
        XCTAssertFalse(window.isDocumentEdited)
    }

    func testAppKitCloseActionHonorsTheGuard() {
        let window = window()
        var decision = ComposeWindowGuardian.Decision.cancel
        let guardian = ComposeWindowGuardian(registry: ComposeWindowRegistry()) { _, _ in decision }
        guardian.configure(document: ComposeDocument(text: "Unsaved draft"), save: { false })
        guardian.attach(to: window)
        defer {
            guardian.detach()
            window.close()
        }
        window.orderBack(nil)
        XCTAssertTrue(window.isVisible)
        window.performClose(nil)
        XCTAssertTrue(window.isVisible, "Cancel must veto the native Close action")
        decision = .discard
        window.performClose(nil)
        XCTAssertFalse(window.isVisible)
    }

    private final class VetoDelegate: NSObject, NSWindowDelegate {
        var closeRequests = 0
        var resizeNotifications = 0

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            closeRequests += 1
            return false
        }

        func windowDidResize(_ notification: Notification) {
            resizeNotifications += 1
        }
    }
}
