import Foundation
import UIKit

/// On-device app list via MCM (no pairing / no LocalDevVPN).
enum AppDiscoveryService {
    /// MCM class 2 = application data containers.
    private static let applicationClass: UInt64 = 2
    private static let enumerateLimit: UInt = 2048

    /// Lists identifiers then resolves paths; filters system Apple apps when `thirdPartyOnly`.
    static func discover(thirdPartyOnly: Bool = true, measureSize: Bool = false) -> [InstalledApp] {
        var enumError: NSString?
        let identifiers = MCMEnumerateIdentifiersForClass(applicationClass, enumerateLimit, &enumError) ?? []

        var apps: [InstalledApp] = []
        apps.reserveCapacity(identifiers.count)

        for raw in identifiers {
            let bundleID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty else { continue }
            if thirdPartyOnly && isSystemBundle(bundleID) { continue }

            var pathError: NSString?
            let path = MCMActivateContainerPath(applicationClass, bundleID, false, &pathError)
            let root = path.flatMap { PathSafety.isAppDataRoot(URL(fileURLWithPath: $0)) ? $0 : nil }

            var size: Int64 = 0
            if measureSize, let root {
                size = directorySize(at: root)
            }

            let name = displayName(for: bundleID, containerPath: root)
            apps.append(
                InstalledApp(
                    bundleID: bundleID,
                    displayName: name,
                    dataContainerPath: root,
                    dataSizeBytes: size,
                    icon: nil
                )
            )
        }

        return apps.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func isSystemBundle(_ id: String) -> Bool {
        id.hasPrefix("com.apple.")
            || id.hasPrefix("com.apple")
            || id.hasPrefix("systemgroup.")
            || id == "com.apple.mobile.MobileHouseArrest"
    }

    private static func displayName(for bundleID: String, containerPath: String?) -> String {
        if let containerPath {
            let meta = (containerPath as NSString)
                .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            if let data = try? Data(contentsOf: URL(fileURLWithPath: meta)),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                if let info = plist["MCMMetadataInfo"] as? [String: Any] {
                    if let dn = info["CFBundleDisplayName"] as? String, !dn.isEmpty { return dn }
                    if let n = info["CFBundleName"] as? String, !n.isEmpty { return n }
                }
            }
        }
        // Fallback: last reverse-DNS component
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
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
