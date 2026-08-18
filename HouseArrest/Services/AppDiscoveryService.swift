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
                byID[bundleID] = InstalledApp(
                    bundleID: bundleID,
                    displayName: lastComponent(bundleID),
                    dataContainerPath: path,
                    icon: nil
                )
            }
        }

        return enrich(byID).values.sorted {
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
            byID[bundleID] = InstalledApp(
                bundleID: bundleID,
                displayName: (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? lastComponent(bundleID),
                dataContainerPath: path,
                icon: nil
            )
        }
    }

    private static func enrich(_ apps: [String: InstalledApp]) -> [String: InstalledApp] {
        let wanted = Set(apps.keys)
        let bundles = loadBundleCatalog(matching: wanted)
        var result: [String: InstalledApp] = [:]
        for (id, app) in apps {
            var names: [String?] = []
            if let path = app.dataContainerPath {
                names.append(readContainerMetadata(path)?.name)
            }
            names.append(bundles[id]?.name)
            names.append(app.displayName)
            result[id] = InstalledApp(
                bundleID: id,
                displayName: preferredName(bundleID: id, candidates: names),
                dataContainerPath: app.dataContainerPath,
                icon: bundles[id]?.icon ?? HAIconForBundleID(id)
            )
        }
        return result
    }

    private static func readContainerMetadata(_ container: String) -> (name: String, bundleID: String)? {
        let meta = (container as NSString).appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist"
        )
        var pathC = Array(meta.utf8CString)
        let handle = bad_query(&pathC, true, nil, false)
        defer { if handle >= 0 { bad_query_release(handle) } }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: meta)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        let bid = (plist["MCMMetadataIdentifier"] as? String) ?? ""
        var name: String?
        if let info = plist["MCMMetadataInfo"] as? [String: Any] {
            name = stringValue(info["CFBundleDisplayName"]) ?? stringValue(info["CFBundleName"])
        }
        guard let name, !name.isEmpty else { return nil }
        return (name, bid)
    }

    private static func loadBundleCatalog(matching wanted: Set<String>) -> [String: (name: String, icon: UIImage?)] {
        var result: [String: (name: String, icon: UIImage?)] = [:]
        guard !wanted.isEmpty else { return result }

        let roots = [
            "/var/containers/Bundle/Application",
            "/private/var/containers/Bundle/Application"
        ]
        for root in roots where result.count < wanted.count {
            var rootC = Array(root.utf8CString)
            guard let listed = bad_query_list(&rootC, 400_000) else { continue }
            let text = String(cString: listed)
            free(listed)
            for raw in text.split(separator: "\n") {
                if result.count >= wanted.count { break }
                let dir = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !dir.isEmpty, UUID(uuidString: (dir as NSString).lastPathComponent) != nil else { continue }
                var dirC = Array(dir.utf8CString)
                let handle = bad_query(&dirC, true, nil, false)
                let children = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                if handle >= 0 { bad_query_release(handle) }
                for child in children where child.hasSuffix(".app") {
                    let appPath = (dir as NSString).appendingPathComponent(child)
                    if let parsed = readAppBundle(at: appPath), wanted.contains(parsed.id) {
                        result[parsed.id] = (parsed.name, parsed.icon)
                    }
                }
            }
        }
        return result
    }

    private static func readAppBundle(at appPath: String) -> (id: String, name: String, icon: UIImage?)? {
        var pathC = Array(appPath.utf8CString)
        let handle = bad_query(&pathC, true, nil, false)
        defer { if handle >= 0 { bad_query_release(handle) } }

        let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: infoPath)),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let bundleID = stringValue(info["CFBundleIdentifier"])
        else { return nil }

        let name = stringValue(info["CFBundleDisplayName"])
            ?? stringValue(info["CFBundleName"])
            ?? lastComponent(bundleID)
        return (bundleID, name, icon(in: appPath, info: info))
    }

    private static func icon(in appPath: String, info: [String: Any]) -> UIImage? {
        var names: [String] = []
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let list = primary["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: list)
        }
        if let list = info["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: list)
        }
        if let file = info["CFBundleIconFile"] as? String {
            names.append(file)
        }
        names.append(contentsOf: ["AppIcon60x60@2x", "AppIcon76x76@2x~ipad", "AppIcon", "Icon@2x", "Icon"])

        for name in names {
            let base = (name as NSString).deletingPathExtension
            for file in [name, base + ".png", base + "@2x.png", base + "@3x.png"] {
                let path = (appPath as NSString).appendingPathComponent(file)
                if let image = UIImage(contentsOfFile: path) { return image }
            }
        }
        return nil
    }

    private static func preferredName(bundleID: String, candidates: [String?]) -> String {
        let tail = lastComponent(bundleID)
        for raw in candidates {
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  value.caseInsensitiveCompare(bundleID) != .orderedSame
            else { continue }
            if value.caseInsensitiveCompare(tail) == .orderedSame { continue }
            return value
        }
        return tail
    }

    private static func lastComponent(_ bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
