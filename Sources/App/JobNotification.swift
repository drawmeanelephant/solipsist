import AppKit
import Foundation
import UserNotifications

@MainActor
enum JobNotificationDispatcher {
    static func notifyIfBackgrounded(
        verb: CoordinatorVerb,
        exit: Int32?,
        duration: Duration
    ) {
        guard !NSApplication.shared.isActive else { return }

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Solipsist"
        let exitStr = exit.map { "exit \($0)" } ?? "exit 0"
        content.body = "\(verb.rawValue.capitalized) finished · \(exitStr)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "solipsist-job-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { _ in }
    }
}
