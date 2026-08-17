import SwiftUI

/// Standard empty-state for the play slot, the drawer, and companion hosts.
/// Prefer this over ad-hoc stacks so the chrome stays one voice.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let actionTitle, let action {
                ContentUnavailableView {
                    Label(title, systemImage: systemImage)
                } description: {
                    Text(message)
                } actions: {
                    Button(actionTitle, action: action)
                }
            } else {
                ContentUnavailableView {
                    Label(title, systemImage: systemImage)
                } description: {
                    Text(message)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
