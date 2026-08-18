import SwiftUI

/// Settings scene root. One tab now so later panes slot in without a new scene.
struct SettingsRoot: View {
    var body: some View {
        TabView {
            SourcesSettingsPane()
                .tabItem {
                    Label("Sources", systemImage: "folder")
                }
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
