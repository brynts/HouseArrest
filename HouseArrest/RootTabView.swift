import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView(selection: $appModel.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            AppsView()
                .tabItem { Label("Apps", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.apps)

            // Keep Patches reachable while Apps detail Patch action is scaffolded.
            PatchesView()
                .tabItem { Label("Patches", systemImage: "shippingbox.fill") }
                .tag(AppTab.patches)
        }
        .tint(HATheme.accent)
    }
}

enum AppTab: Hashable {
    case home
    case apps
    case patches
}
