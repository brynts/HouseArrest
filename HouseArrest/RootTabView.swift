import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView(selection: $appModel.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            PatchesView()
                .tabItem { Label("Patches", systemImage: "shippingbox.fill") }
                .tag(AppTab.patches)
        }
        .tint(HATheme.accent)
    }
}

enum AppTab: Hashable {
    case home
    case patches
}
