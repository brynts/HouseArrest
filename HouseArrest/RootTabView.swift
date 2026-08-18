import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView(selection: $appModel.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Apps", systemImage: "square.grid.2x2.fill", value: AppTab.apps) {
                AppsView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(HATheme.accent)
    }
}

enum AppTab: Hashable {
    case home
    case apps
    case settings
}
