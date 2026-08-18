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
    static var lastProbe = ""

    static func discover(thirdPartyOnly: Bool = true) -> [InstalledApp] {
        lastProbe = ""
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
                displayName: lastComponent(bundleID),
                dataContainerPath: path,
                icon: nil
            )
        }
    }

    private static func enrich(_ apps: [String: InstalledApp]) -> [String: InstalledApp] {
        let wanted = Set(apps.keys)
        let bundles = loadBundleCatalog(matching: wanted)
        var named = 0
        var iconed = 0
        var samples: [String] = []
        var result: [String: InstalledApp] = [:]

        for (id, app) in apps {
            var names: [String] = []
            if let path = app.dataContainerPath, let meta = readContainerMetadata(path) {
                names.append(contentsOf: meta.names)
                if samples.count < 3 {
                    samples.append("meta \(id) info=\(meta.infoDump) names=\(meta.names.joined(separator: "|"))")
                }
            }
            if let bundle = bundles[id] {
                names.append(contentsOf: bundle.names)
            }

            let icon = usableIcon(bundles[id]?.icon)
            if icon != nil { iconed += 1 }
            let name = preferredName(bundleID: id, candidates: names)
            if name.caseInsensitiveCompare(lastComponent(id)) != .orderedSame { named += 1 }

            result[id] = InstalledApp(
                bundleID: id,
                displayName: name,
                dataContainerPath: app.dataContainerPath,
                icon: icon
            )
        }

        lastProbe = (["enrich apps=\(apps.count) named=\(named) icons=\(iconed) bundles=\(bundles.count)"] + samples)
            .joined(separator: "\n")
        return result
    }

    private static func readContainerMetadata(_ container: String) -> (names: [String], infoDump: String)? {
        let meta = (container as NSString).appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist"
        )
        guard let plist = readPlist(at: meta) else { return nil }
        var dump = "nil"
        if let info = plist["MCMMetadataInfo"] {
            dump = describe(info)
        }
        return (displayNames(in: plist), dump)
    }

    private static func loadBundleCatalog(matching wanted: Set<String>) -> [String: (names: [String], icon: UIImage?)] {
        var result: [String: (names: [String], icon: UIImage?)] = [:]
        guard !wanted.isEmpty else { return result }

        let roots = [
            "/var/containers/Bundle/Application",
            "/private/var/containers/Bundle/Application"
        ]
        var listed = 0
        var parsed = 0
        for root in roots {
            var rootC = Array(root.utf8CString)
            guard let raw = bad_query_list(&rootC, 400_000) else {
                lastProbe += "\nbundle-list \(root) NULL"
                continue
            }
            let text = String(cString: raw)
            free(raw)
            let lines = text.split(separator: "\n").map(String.init)
            listed += lines.count
            lastProbe += "\nbundle-list \(root) entries=\(lines.count) sample=\(lines.first ?? "")"

            for line in lines {
                let dir = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !dir.isEmpty, UUID(uuidString: (dir as NSString).lastPathComponent) != nil else { continue }
                var dirC = Array(dir.utf8CString)
                let handle = bad_query(&dirC, true, nil, false)
                let children = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                if handle >= 0 { bad_query_release(handle) }

                if let itunes = readPlist(at: (dir as NSString).appendingPathComponent("iTunesMetadata.plist")),
                   let bid = usableName(itunes["softwareVersionBundleId"]) ?? usableName(itunes["bundleId"]),
                   wanted.contains(bid) {
                    var names = displayNames(in: itunes)
                    if let item = usableName(itunes["itemName"]) { names.insert(item, at: 0) }
                    if result[bid] == nil {
                        result[bid] = (names, nil)
                    } else {
                        result[bid]?.names.append(contentsOf: names)
                    }
                }

                for child in children where child.hasSuffix(".app") {
                    let appPath = (dir as NSString).appendingPathComponent(child)
                    guard let parsedApp = readAppBundle(at: appPath), wanted.contains(parsedApp.id) else { continue }
                    parsed += 1
                    result[parsedApp.id] = (parsedApp.names, parsedApp.icon)
                }
            }
        }
        lastProbe += "\nbundle-scan listed=\(listed) parsed=\(parsed) matched=\(result.count)"
        return result
    }

    private static func readAppBundle(at appPath: String) -> (id: String, names: [String], icon: UIImage?)? {
        var pathC = Array(appPath.utf8CString)
        let handle = bad_query(&pathC, true, nil, false)
        defer { if handle >= 0 { bad_query_release(handle) } }

        guard let info = readPlist(at: (appPath as NSString).appendingPathComponent("Info.plist")),
              let bundleID = usableName(info["CFBundleIdentifier"])
        else { return nil }

        var names = displayNames(in: info)
        names.append(contentsOf: localizedDisplayNames(in: appPath))
        return (bundleID, names, pngIcon(in: appPath, info: info))
    }

    private static func localizedDisplayNames(in appPath: String) -> [String] {
        let children = (try? FileManager.default.contentsOfDirectory(atPath: appPath)) ?? []
        var names: [String] = []
        for child in children where child.hasSuffix(".lproj") {
            let stringsPath = ((appPath as NSString)
                .appendingPathComponent(child) as NSString)
                .appendingPathComponent("InfoPlist.strings")
            if let dict = NSDictionary(contentsOfFile: stringsPath) as? [String: Any] {
                names.append(contentsOf: displayNames(in: dict))
            }
        }
        return names
    }

    private static func displayNames(in dict: [String: Any]) -> [String] {
        var names: [String] = []
        for key in ["CFBundleDisplayName", "CFBundleName", "itemName", "name"] {
            if let value = usableName(dict[key]) { names.append(value) }
        }
        if let info = dict["MCMMetadataInfo"] as? [String: Any] {
            names.append(contentsOf: displayNames(in: info))
        }
        return names
    }

    private static func usableName(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") { return nil }
        return trimmed
    }

    private static func pngIcon(in appPath: String, info: [String: Any]) -> UIImage? {
        var names: [String] = []
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let list = primary["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: list)
        }
        if let list = info["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: list)
        }
        names.append(contentsOf: ["AppIcon60x60@2x", "AppIcon", "Icon@2x", "Icon"])
        for name in names {
            let base = (name as NSString).deletingPathExtension
            for file in [name, base + ".png", base + "@2x.png", base + "@3x.png"] {
                if let image = usableIcon(UIImage(contentsOfFile: (appPath as NSString).appendingPathComponent(file))) {
                    return image
                }
            }
        }
        return nil
    }

    private static func usableIcon(_ image: UIImage?) -> UIImage? {
        guard let image, image.size.width >= 16, image.size.height >= 16 else { return nil }
        return image
    }

    private static func readPlist(at path: String) -> [String: Any]? {
        var pathC = Array(path.utf8CString)
        let handle = bad_query(&pathC, true, nil, false)
        defer { if handle >= 0 { bad_query_release(handle) } }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist
    }

    private static func describe(_ value: Any) -> String {
        if let dict = value as? [String: Any] {
            return "dict[\(dict.keys.sorted().joined(separator: ","))]"
        }
        if let array = value as? [Any] {
            return "array(\(array.count))"
        }
        if let string = value as? String {
            return "str:\(string.prefix(60))"
        }
        return String(describing: type(of: value))
    }

    private static func preferredName(bundleID: String, candidates: [String]) -> String {
        let tail = lastComponent(bundleID)
        for raw in candidates {
            guard let value = usableName(raw) else { continue }
            if value.caseInsensitiveCompare(bundleID) == .orderedSame { continue }
            if value.caseInsensitiveCompare(tail) == .orderedSame { continue }
            return value
        }
        return tail
    }

    private static func lastComponent(_ bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
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
