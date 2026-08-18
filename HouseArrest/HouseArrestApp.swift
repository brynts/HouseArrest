import SwiftUI

@main
struct HouseArrestApp: App {
    @StateObject private var appModel = AppModel()
    @AppStorage("ha.appearance") private var appearanceRaw = HAAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appModel)
                .preferredColorScheme(HAAppearance(rawValue: appearanceRaw)?.colorScheme)
        }
    }
}
