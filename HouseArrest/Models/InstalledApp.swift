import Foundation
import UIKit

/// Third-party (or user) application discovered on-device via MCM.
struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleID }
    var bundleID: String
    var displayName: String
    /// Data container root when resolved (`/var/mobile/Containers/Data/Application/<UUID>`).
    var dataContainerPath: String?
    /// Approximate data-container size in bytes (0 if not measured).
    var dataSizeBytes: Int64
    var icon: UIImage?

    var isThirdParty: Bool {
        !bundleID.hasPrefix("com.apple.")
            && !bundleID.hasPrefix("com.apple")
            && !bundleID.hasPrefix("systemgroup.")
    }

    var dataSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: dataSizeBytes, countStyle: .file)
    }
}
