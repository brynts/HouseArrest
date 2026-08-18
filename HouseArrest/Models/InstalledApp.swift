import Foundation
import UIKit

struct InstalledApp: Identifiable {
    var id: String { bundleID }
    var bundleID: String
    var displayName: String
    var dataContainerPath: String?
    var dataSizeBytes: Int64
    var icon: UIImage?

    var dataSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: dataSizeBytes, countStyle: .file)
    }
}

extension InstalledApp: Hashable {
    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.bundleID == rhs.bundleID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
    }
}
