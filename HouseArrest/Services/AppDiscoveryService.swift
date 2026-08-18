import Foundation
import UIKit

enum AppDiscoveryService {
    static func discover(thirdPartyOnly: Bool = true, measureSize: Bool = false) -> [InstalledApp] {
        let catalog = HAInstalledAppCatalog()
        var apps: [InstalledApp] = []
        apps.reserveCapacity(catalog.count)

        for (bundleID, info) in catalog {
            if thirdPartyOnly && isSystemBundle(bundleID) { continue }

            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? bundleID.split(separator: ".").last.map(String.init)
                ?? bundleID
            var path = info["container"] as? String
            if path == nil || path?.isEmpty == true {
                var err: NSString?
                path = MCMActivateContainerPath(2, bundleID, false, &err)
            }
            if let p = path, !PathSafety.isAppDataRoot(URL(fileURLWithPath: p)) {
                path = nil
            }

            var size: Int64 = 0
            if measureSize, let path {
                size = directorySize(at: path)
            }

            apps.append(
                InstalledApp(
                    bundleID: bundleID,
                    displayName: name,
                    dataContainerPath: path,
                    dataSizeBytes: size,
                    icon: HAIconForBundleID(bundleID)
                )
            )
        }

        return apps.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func isSystemBundle(_ id: String) -> Bool {
        id.hasPrefix("com.apple.")
            || id.hasPrefix("systemgroup.")
            || id == "com.apple.mobile.MobileHouseArrest"
    }

    private static func directorySize(at path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }
}
