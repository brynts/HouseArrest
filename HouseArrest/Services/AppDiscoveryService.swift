import Foundation
import UIKit

enum AppDiscoveryService {
    static func discover(thirdPartyOnly: Bool = true, measureSize: Bool = false) -> [InstalledApp] {
        var byID: [String: InstalledApp] = [:]

        let catalog = HAInstalledAppCatalog()
        merge(catalog, into: &byID, thirdPartyOnly: thirdPartyOnly, measureSize: measureSize)

        if byID.isEmpty {
            let candidates = LaunchServicesStore.identifiers()
            var resolved = 0
            for bundleID in candidates {
                if thirdPartyOnly && isSystemBundle(bundleID) { continue }
                var err: NSString?
                guard let path = MCMActivateContainerPath(2, bundleID, false, &err),
                      PathSafety.isAppDataRoot(URL(fileURLWithPath: path))
                else { continue }
                resolved += 1
                byID[bundleID] = makeApp(
                    bundleID: bundleID,
                    name: bundleID.split(separator: ".").last.map(String.init) ?? bundleID,
                    path: path,
                    measureSize: measureSize
                )
            }
            // probe is stored on LaunchServicesStore.lastProbe
            _ = resolved
        }

        return byID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func isSystemBundle(_ id: String) -> Bool {
        id.hasPrefix("com.apple.")
            || id.hasPrefix("systemgroup.")
            || id == "com.apple.mobile.MobileHouseArrest"
    }

    private static func merge(
        _ catalog: [AnyHashable: Any],
        into byID: inout [String: InstalledApp],
        thirdPartyOnly: Bool,
        measureSize: Bool
    ) {
        for (rawID, rawInfo) in catalog {
            guard let bundleID = rawID as? String else { continue }
            if thirdPartyOnly && isSystemBundle(bundleID) { continue }
            let info = rawInfo as? [String: Any] ?? [:]
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
            byID[bundleID] = makeApp(bundleID: bundleID, name: name, path: path, measureSize: measureSize)
        }
    }

    private static func makeApp(
        bundleID: String,
        name: String,
        path: String?,
        measureSize: Bool
    ) -> InstalledApp {
        var size: Int64 = 0
        if measureSize, let path {
            size = directorySize(at: path)
        }
        return InstalledApp(
            bundleID: bundleID,
            displayName: name,
            dataContainerPath: path,
            dataSizeBytes: size,
            icon: HAIconForBundleID(bundleID)
        )
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
