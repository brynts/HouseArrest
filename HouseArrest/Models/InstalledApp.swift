import Foundation
import UIKit

enum AppIconStore {
    private static var icons: [String: UIImage] = [:]

    static func set(_ icon: UIImage?, for bundleID: String) {
        if let icon {
            icons[bundleID] = icon
        }
    }

    static func icon(for bundleID: String) -> UIImage? {
        icons[bundleID]
    }
}

struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleID }
    var bundleID: String
    var displayName: String
    var dataContainerPath: String?

    var icon: UIImage? { AppIconStore.icon(for: bundleID) }
}
