import SwiftUI

/// Settings scene root. One tab now so later panes slot in without a new scene.
struct SettingsRoot: View {
    var body: some View {
        TabView {
            SourcesSettingsPane()
                .tabItem {
                    Label("Sources", systemImage: "folder")
                }
            EngineSettingsPane()
                .tabItem {
                    Label("Engine", systemImage: "cpu")
                }
        }
        .frame(minWidth: 540, minHeight: 380)
    }
}
