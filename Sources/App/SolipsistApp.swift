import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pending: [URL] = []
    var openFolder: (@Sendable (URL) -> Void)? {
        didSet {
            guard let openFolder else { return }
            pending.forEach(openFolder)
            pending.removeAll()
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        deliver(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        filenames.forEach { deliver(URL(fileURLWithPath: $0)) }
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(deliver)
    }

    private func deliver(_ url: URL) {
        if let openFolder {
            openFolder(url)
        } else {
            pending.append(url)
        }
    }
}

@main
struct SolipsistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = WorkspaceStore()
    @State private var runtime = AppRuntime()
    @State private var inspectorPresented = true

    var body: some Scene {
        WindowGroup {
            MainWindow(inspectorPresented: $inspectorPresented)
                .environment(store)
                .environment(runtime)
                .onAppear {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                    appDelegate.openFolder = { url in
                        Task { @MainActor in
                            store.openFromSystem(url)
                        }
                    }
                    store.refreshRecentFolders()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification
                )) { _ in
                    runtime.coordinator.terminateAll(runtime: runtime)
                }
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

        Window("Solipsist Help", id: "help") {
            HelpWindow()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 560, height: 480)

        Window("About Solipsist", id: "about") {
            AboutWindow()
                .environment(runtime)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 280)
    }
}
