import Foundation
import UIKit

struct ContainerUsage {
    var documents: Int64 = 0
    var caches: Int64 = 0
    var tmp: Int64 = 0

    var documentsLabel: String { Self.format(documents) }
    var cachesLabel: String { Self.format(caches) }
    var tmpLabel: String { Self.format(tmp) }

    private static func format(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

enum AppDiscoveryService {
    static func discover(thirdPartyOnly: Bool = true) -> [InstalledApp] {
        var byID: [String: InstalledApp] = [:]

        let catalog = HAInstalledAppCatalog()
        merge(catalog, into: &byID, thirdPartyOnly: thirdPartyOnly)

        if byID.isEmpty {
            for bundleID in LaunchServicesStore.identifiers() {
                if thirdPartyOnly && isSystemBundle(bundleID) { continue }
                var err: NSString?
                guard let path = MCMActivateContainerPath(2, bundleID, false, &err),
                      PathSafety.isAppDataRoot(URL(fileURLWithPath: path))
                else { continue }
                byID[bundleID] = makeApp(bundleID: bundleID, fallbackName: nil, path: path)
            }
        }

        return byID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func usage(for path: String) -> ContainerUsage {
        var pathC = Array(path.utf8CString)
        let handle = bad_query(&pathC, true, nil, false)
        defer { if handle >= 0 { bad_query_release(handle) } }

        let root = path as NSString
        return ContainerUsage(
            documents: directorySize(at: root.appendingPathComponent("Documents")),
            caches: directorySize(at: root.appendingPathComponent("Library/Caches")),
            tmp: directorySize(at: root.appendingPathComponent("tmp"))
        )
    }

    static func isSystemBundle(_ id: String) -> Bool {
        id.hasPrefix("com.apple.")
            || id.hasPrefix("systemgroup.")
            || id == "com.apple.mobile.MobileHouseArrest"
    }

    private static func merge(
        _ catalog: [AnyHashable: Any],
        into byID: inout [String: InstalledApp],
        thirdPartyOnly: Bool
    ) {
        for (rawID, rawInfo) in catalog {
            guard let bundleID = rawID as? String else { continue }
            if thirdPartyOnly && isSystemBundle(bundleID) { continue }
            let info = rawInfo as? [String: Any] ?? [:]
            var path = info["container"] as? String
            if path == nil || path?.isEmpty == true {
                var err: NSString?
                path = MCMActivateContainerPath(2, bundleID, false, &err)
            }
            if let p = path, !PathSafety.isAppDataRoot(URL(fileURLWithPath: p)) {
                path = nil
            }
            byID[bundleID] = makeApp(
                bundleID: bundleID,
                fallbackName: info["name"] as? String,
                path: path
            )
        }
    }

    private static func makeApp(bundleID: String, fallbackName: String?, path: String?) -> InstalledApp {
        let presented = HAPresentationForBundleID(bundleID)
        let resolved = (presented["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let fallback = fallbackName.flatMap { $0.isEmpty ? nil : $0 }
        let name = preferredName(bundleID: bundleID, candidates: [resolved, fallback])
        return InstalledApp(
            bundleID: bundleID,
            displayName: name,
            dataContainerPath: path,
            icon: presented["icon"] as? UIImage ?? HAIconForBundleID(bundleID)
        )
    }

    private static func preferredName(bundleID: String, candidates: [String?]) -> String {
        let tail = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        for raw in candidates {
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  value.caseInsensitiveCompare(bundleID) != .orderedSame,
                  value.caseInsensitiveCompare(tail) != .orderedSame
            else { continue }
            return value
        }
        return tail
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
