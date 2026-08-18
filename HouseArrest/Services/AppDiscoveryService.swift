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
        var named = 0
        var iconed = 0
        var bundles = 0
        var result: [String: InstalledApp] = [:]
        var samples: [String] = []

        for (id, app) in apps {
            var names: [String?] = []
            if let path = app.dataContainerPath, let meta = readContainerMetadata(path) {
                names.append(contentsOf: meta.names)
                if samples.count < 4 {
                    samples.append("meta \(id) keys=\(meta.keys.joined(separator: ",")) names=\(meta.names.joined(separator: "|"))")
                }
            }

            if let bundle = resolveBundle(for: id) {
                bundles += 1
                names.append(contentsOf: bundle.names)
                if samples.count < 8 {
                    samples.append("bundle \(id) path=\(bundle.path) names=\(bundle.names.joined(separator: "|")) icon=\(bundle.icon != nil)")
                }
            }

            let icon = springBoardIcon(for: id) ?? resolveBundle(for: id)?.icon
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

        lastProbe = (["enrich apps=\(apps.count) named=\(named) icons=\(iconed) bundles=\(bundles)"] + samples)
            .joined(separator: "\n")
        return result
    }

    private static func readContainerMetadata(_ container: String) -> (keys: [String], names: [String])? {
        let meta = (container as NSString).appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist"
        )
        var pathC = Array(meta.utf8CString)
        let handle = bad_query(&pathC, true, nil, false)
        defer { if handle >= 0 { bad_query_release(handle) } }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: meta)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return (Array(plist.keys).sorted(), displayNames(in: plist))
    }

    private static func resolveBundle(for bundleID: String) -> (path: String, names: [String], icon: UIImage?)? {
        for cls: UInt64 in [1, 8] {
            var err: NSString?
            guard let root = MCMActivateContainerPath(cls, bundleID, false, &err) else { continue }
            var rootC = Array(root.utf8CString)
            let handle = bad_query(&rootC, true, nil, false)
            let children = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            if handle >= 0 { bad_query_release(handle) }
            let appName = children.first(where: { $0.hasSuffix(".app") }) ?? ((root as NSString).lastPathComponent.hasSuffix(".app") ? "" : nil)
            let appPath: String
            if let appName, !appName.isEmpty {
                appPath = (root as NSString).appendingPathComponent(appName)
            } else if root.hasSuffix(".app") {
                appPath = root
            } else {
                continue
            }
            if let parsed = readAppBundle(at: appPath) {
                return (appPath, parsed.names, parsed.icon)
            }
        }

        if let path = mcmAppContainerPath(bundleID) {
            var pathC = Array(path.utf8CString)
            let handle = bad_query(&pathC, true, nil, false)
            let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            if handle >= 0 { bad_query_release(handle) }
            if let appName = children.first(where: { $0.hasSuffix(".app") }) {
                return readAppBundle(at: (path as NSString).appendingPathComponent(appName))
                    .map { ((path as NSString).appendingPathComponent(appName), $0.names, $0.icon) }
            }
        }
        return nil
    }

    private static func mcmAppContainerPath(_ bundleID: String) -> String? {
        guard let cls = NSClassFromString("MCMAppContainer") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("containerWithIdentifier:createIfNecessary:existed:error:")
        guard cls.responds(to: sel) else { return nil }
        let unmanaged = cls.perform(sel, with: bundleID, with: false)
        // perform:with:with: only passes 2 args; use ObjC runtime via HAPresentation fallback.
        _ = unmanaged
        return nil
    }

    private static func readAppBundle(at appPath: String) -> (names: [String], icon: UIImage?)? {
        var pathC = Array(appPath.utf8CString)
        let handle = bad_query(&pathC, true, nil, false)
        defer { if handle >= 0 { bad_query_release(handle) } }

        let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: infoPath)),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }

        var names = displayNames(in: info)
        names.append(contentsOf: localizedDisplayNames(in: appPath))
        return (names, pngIcon(in: appPath, info: info))
    }

    private static func localizedDisplayNames(in appPath: String) -> [String] {
        let children = (try? FileManager.default.contentsOfDirectory(atPath: appPath)) ?? []
        var names: [String] = []
        for child in children where child.hasSuffix(".lproj") {
            let stringsPath = ((appPath as NSString)
                .appendingPathComponent(child) as NSString)
                .appendingPathComponent("InfoPlist.strings")
            guard let dict = NSDictionary(contentsOfFile: stringsPath) as? [String: Any] else { continue }
            names.append(contentsOf: displayNames(in: dict))
        }
        return names
    }

    private static func displayNames(in dict: [String: Any]) -> [String] {
        var names: [String] = []
        let keys = [
            "CFBundleDisplayName",
            "CFBundleName",
            "MCMMetadataDisplayName",
            "itemName",
            "name"
        ]
        for key in keys {
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
                if let image = UIImage(contentsOfFile: (appPath as NSString).appendingPathComponent(file)) {
                    return image
                }
            }
        }
        return nil
    }

    private static func springBoardIcon(for bundleID: String) -> UIImage? {
        let sel = NSSelectorFromString("_applicationIconImageForBundleIdentifier:format:scale:")
        guard UIImage.responds(to: sel) else { return nil }
        typealias Fn = @convention(c) (AnyClass, Selector, NSString, Int, Double) -> UIImage?
        let impl = unsafeBitCast(UIImage.method(for: sel)!, to: Fn.self)
        for format in [2, 1, 0, 10] {
            if let image = impl(UIImage.self, sel, bundleID as NSString, format, 3.0) {
                return image
            }
        }
        return HAIconForBundleID(bundleID)
    }

    private static func preferredName(bundleID: String, candidates: [String?]) -> String {
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
