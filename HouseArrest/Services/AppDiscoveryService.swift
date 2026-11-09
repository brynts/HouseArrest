import Foundation
import UIKit
import Darwin

enum HAWork {
    static let queue = DispatchQueue(label: "ha.work")
}

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
    private static var cachedApps: [InstalledApp] = []
    private static var didFullScan = false
    private static var seenUUIDs = Set<String>()
    private static var itunesCache: [String: (name: String, icon: UIImage?)] = [:]

    static func discover(
        thirdPartyOnly: Bool = true,
        progress: ((String, Int, Int) -> Void)? = nil
    ) -> [InstalledApp] {
        let all = didFullScan
            ? refresh(progress: progress)
            : fullScan(progress: progress)
        return all.filter { thirdPartyOnly ? !$0.isSystem : $0.isSystem }
    }

    static func usage(for path: String) -> ContainerUsage {
        _ = GrantCache.grantOnce(path: path)
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

    private static func fullScan(
        progress: ((String, Int, Int) -> Void)?
    ) -> [InstalledApp] {
        HALog.write("scan start")
        lastProbe = ""
        var byID: [String: InstalledApp] = [:]
        progress?("Finding apps", 0, 0)

        let catalog = HAInstalledAppCatalog()
        merge(catalog, into: &byID)
        if byID.isEmpty {
            for bundleID in LaunchServicesStore.identifiers() {
                addIfNeeded(bundleID, into: &byID)
            }
        }
        if byID.isEmpty {
            merge(mcmAppCatalog(), into: &byID)
        }
        if !byID.keys.contains(where: { !isSystemBundle($0) }) {
            merge(leakedAppCatalog(progress: progress), into: &byID)
        }

        let result = enrich(byID, progress: progress).values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        cachedApps = result
        didFullScan = true
        seenUUIDs = Set(result.compactMap { $0.dataContainerPath.map(containerUUID) })
        lastProbe = "scan apps=\(result.count) seen=\(seenUUIDs.count)\n" + lastProbe
        HALog.write("scan done apps=\(result.count) seen=\(seenUUIDs.count)")
        return result
    }

    private static func refresh(
        progress: ((String, Int, Int) -> Void)?
    ) -> [InstalledApp] {
        progress?("Updating apps", 0, 0)
        var byID = Dictionary(uniqueKeysWithValues: cachedApps.map { ($0.bundleID, $0) })
        var droppedIDs: [String] = []
        for (id, app) in byID {
            guard let path = app.dataContainerPath,
                  FileManager.default.fileExists(atPath: path) else {
                byID.removeValue(forKey: id)
                droppedIDs.append(id)
                MCMInvalidateContainer(2, id, false)
                HALog.write("refresh drop \(id)")
                continue
            }
        }

        let folders = listApplicationContainers()
        let newFolders = folders.filter { !seenUUIDs.contains(containerUUID($0)) }
        seenUUIDs.formUnion(folders.map(containerUUID))
        HALog.write("refresh folders=\(folders.count) new=\(newFolders.count) retry=\(droppedIDs.count)")

        var added: [String: InstalledApp] = [:]
        for folder in newFolders {
            guard !haIsContainerParent(folder) else { continue }
            var pathC = Array(folder.utf8CString)
            let handle = bad_query(&pathC, true, nil, false)
            defer { if handle >= 0 { bad_query_release(handle) } }
            guard let bundleID = bundleID(fromContainer: folder) else { continue }
            if byID[bundleID] != nil { continue }
            byID[bundleID] = InstalledApp(
                bundleID: bundleID,
                displayName: lastComponent(bundleID),
                dataContainerPath: folder
            )
            added[bundleID] = byID[bundleID]
            HALog.write("refresh add \(bundleID)")
        }

        for bundleID in droppedIDs {
            guard addIfNeeded(bundleID, into: &byID) else { continue }
            added[bundleID] = byID[bundleID]
            HALog.write("refresh retry \(bundleID)")
        }

        if !added.isEmpty {
            let extra = enrich(added, progress: progress)
            for (id, app) in extra { byID[id] = app }
        }

        let result = byID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        cachedApps = result
        lastProbe = "refresh added=\(added.count) dropped=\(droppedIDs.count) folders=\(folders.count) new=\(newFolders.count)"
        HALog.write("refresh done added=\(added.count) dropped=\(droppedIDs.count) total=\(result.count)")
        return result
    }

    @discardableResult
    private static func addIfNeeded(
        _ bundleID: String,
        into byID: inout [String: InstalledApp]
    ) -> Bool {
        if byID[bundleID] != nil { return false }
        var err: NSString?
        guard let path = MCMActivateContainerPath(2, bundleID, false, &err),
              FileManager.default.fileExists(atPath: path),
              PathSafety.isAppDataRoot(URL(fileURLWithPath: path))
        else { return false }
        byID[bundleID] = InstalledApp(
            bundleID: bundleID,
            displayName: lastComponent(bundleID),
            dataContainerPath: path
        )
        return true
    }

    private static func merge(
        _ catalog: [AnyHashable: Any],
        into byID: inout [String: InstalledApp]
    ) {
        for (rawID, rawInfo) in catalog {
            guard let bundleID = rawID as? String else { continue }
            let info = rawInfo as? [String: Any] ?? [:]
            var path = info["container"] as? String
            if path == nil || path?.isEmpty == true {
                var err: NSString?
                path = MCMContainerPathForIdentifier(2, bundleID, false, &err)
            }
            if let p = path, haIsContainerParent(p) { path = nil }
            byID[bundleID] = InstalledApp(
                bundleID: bundleID,
                displayName: lastComponent(bundleID),
                dataContainerPath: path
            )
        }
    }

    private static func mcmAppCatalog() -> [AnyHashable: Any] {
        HALog.write("mcm enum start")
        var err: NSString?
        let ids = MCMEnumerateIdentifiersForClass(2, 400, &err) ?? []
        HALog.write("mcm enum count=\(ids.count) err=\(err ?? "none") ids=\(ids.prefix(8).joined(separator: ","))")
        var catalog: [AnyHashable: Any] = [:]
        for id in ids where id.contains(".") {
            var pathErr: NSString?
            let path = MCMContainerPathForIdentifier(2, id, false, &pathErr)
            var info: [String: Any] = [:]
            if let path, !path.isEmpty, !haIsContainerParent(path) { info["container"] = path }
            catalog[id] = info
        }
        HALog.write("mcm apps=\(catalog.count)")
        return catalog
    }

    private static func leakedAppCatalog(
        progress: ((String, Int, Int) -> Void)?
    ) -> [AnyHashable: Any] {
        let cached = loadCachedContainers()
        if cached.count > 1 {
            HALog.write("leak cache=\(cached.count)")
            return catalogFromContainerPaths(cached)
        }
        let baseline = ha_baseline_inode()
        HALog.write("leak baseline=\(baseline)")
        guard baseline > 0 else { return [:] }
        let found = NSMutableArray()
        var cursor: UInt64 = 1
        let step: UInt64 = 1_000_000
        while cursor <= baseline {
            let end = min(baseline, cursor &+ step &- 1)
            ha_leak_app_containers(cursor, end, found)
            HALog.write("leak inode=\(end) found=\(found.count)")
            progress?("Reading containers", Int(min(end, UInt64(Int.max))), Int(min(baseline, UInt64(Int.max))))
            if end == baseline { break }
            cursor = end &+ 1
        }
        let paths = found.compactMap { $0 as? String }
        HALog.write("leak paths=\(paths.count)")
        saveCachedContainers(paths)
        return catalogFromContainerPaths(paths)
    }

    private static func catalogFromContainerPaths(_ paths: [String]) -> [AnyHashable: Any] {
        var catalog: [AnyHashable: Any] = [:]
        var named = 0
        for path in paths where !haIsContainerParent(path) {
            let uuid = URL(fileURLWithPath: path).lastPathComponent
            let id = readIdentifier(path) ?? uuid
            if id.contains(".") { named += 1 }
            catalog[id] = ["container": path]
        }
        HALog.write("leak apps=\(catalog.count) named=\(named)")
        return catalog
    }

    /// Bundle id from the container xattr. No sandbox grant: granting here killed the process.
    private static func readIdentifier(_ path: String) -> String? {
        var buf = [CChar](repeating: 0, count: 512)
        let len = getxattr(path, "com.apple.containermanager.identifier", &buf, 511, 0, 0)
        guard len > 0 else { return nil }
        let id = String(cString: buf)
        return id.contains(".") ? id : nil
    }

    private static var containerCacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ha-app-containers.txt")
    }

    private static func loadCachedContainers() -> [String] {
        guard let text = try? String(contentsOf: containerCacheURL, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    private static func saveCachedContainers(_ paths: [String]) {
        let text = paths.joined(separator: "\n")
        try? text.write(to: containerCacheURL, atomically: true, encoding: .utf8)
    }

    private static func listApplicationContainers() -> [String] {
        mcmAppCatalog().values.compactMap { value in
            (value as? [String: Any])?["container"] as? String
        }
    }

    private static func haIsContainerParent(_ path: String) -> Bool {
        let roots = [
            "/var/mobile/Containers/Data/Application",
            "/private/var/mobile/Containers/Data/Application",
            "/var/mobile/Containers/Data/InternalDaemon",
            "/private/var/mobile/Containers/Data/InternalDaemon",
            "/var/mobile/Containers/Data/PluginKitPlugin",
            "/private/var/mobile/Containers/Data/PluginKitPlugin",
            "/var/mobile/Containers/Shared/AppGroup",
            "/private/var/mobile/Containers/Shared/AppGroup"
        ]
        return roots.contains(path)
    }

    private static func bundleID(fromContainer path: String) -> String? {
        let meta = (path as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        var pathC = Array(meta.utf8CString)
        let handle = bad_query(&pathC, true, nil, false)
        defer { if handle >= 0 { bad_query_release(handle) } }
        guard let dict = NSDictionary(contentsOfFile: meta) as? [String: Any] else { return nil }
        if let id = dict["MCMMetadataIdentifier"] as? String, id.contains(".") { return id }
        if let id = dict["MCMApplicationIdentifier"] as? String, id.contains(".") { return id }
        if let info = dict["MCMMetadataInfo"] as? [String: Any],
           let id = info["MCMApplicationIdentifier"] as? String, id.contains(".") {
            return id
        }
        return nil
    }

    private static func containerUUID(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private static func isUUID(_ name: String) -> Bool {
        name.count == 36 && name.utf8.filter { $0 == UInt8(ascii: "-") }.count == 4
    }

    private static func normalizePath(_ path: String) -> String {
        var value = URL(fileURLWithPath: path).standardizedFileURL.path
        if value.hasPrefix("/var/") { value = "/private" + value }
        return value
    }

    private static func enrich(
        _ apps: [String: InstalledApp],
        progress: ((String, Int, Int) -> Void)?
    ) -> [String: InstalledApp] {
        var named = 0
        var iconed = 0
        var itunesHit = 0
        var itunesMiss = 0
        var result: [String: InstalledApp] = [:]
        let lookup = apps.filter { !isSystemBundle($0.key) && $0.key.contains(".") }
        let skipStore = lookup.count > 40
        let total = max(lookup.count, 1)
        var index = 0
        for (id, app) in apps {
            if skipStore || isSystemBundle(id) || !id.contains(".") {
                result[id] = InstalledApp(
                    bundleID: id,
                    displayName: lastComponent(id),
                    dataContainerPath: app.dataContainerPath
                )
                continue
            }
            index += 1
            progress?("Fetching App Store info", index, total)
            var name = lastComponent(id)
            var icon: UIImage?
            if let store = itunesLookup(bundleID: id) {
                itunesHit += 1
                name = store.name
                icon = store.icon
            } else {
                itunesMiss += 1
            }
            AppIconStore.set(icon, for: id)
            if name.caseInsensitiveCompare(lastComponent(id)) != .orderedSame { named += 1 }
            if icon != nil { iconed += 1 }
            result[id] = InstalledApp(
                bundleID: id,
                displayName: name,
                dataContainerPath: app.dataContainerPath
            )
        }
        lastProbe = "itunes hit=\(itunesHit) miss=\(itunesMiss) named=\(named) icons=\(iconed)"
        return result
    }

    private static func itunesLookup(bundleID: String) -> (name: String, icon: UIImage?)? {
        if let cached = itunesCache[bundleID] { return cached }
        if let stored = UserDefaults.standard.string(forKey: "ha.itunes.name.\(bundleID)"),
           !stored.isEmpty {
            let icon = itunesIcon(from: UserDefaults.standard.string(forKey: "ha.itunes.art.\(bundleID)"))
            let value = (stored, icon)
            itunesCache[bundleID] = value
            return value
        }
        for country in ["id", "us", ""] {
            var comps = URLComponents(string: "https://itunes.apple.com/lookup")
            var items = [URLQueryItem(name: "bundleId", value: bundleID)]
            if !country.isEmpty {
                items.append(URLQueryItem(name: "country", value: country))
            }
            comps?.queryItems = items
            guard let url = comps?.url else { continue }
            var request = URLRequest(url: url, timeoutInterval: 8)
            guard let data = try? URLSession.shared.synchronousData(with: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first
            else { continue }
            let name = usableName(first["trackName"])
                ?? usableName(first["trackCensoredName"])
                ?? lastComponent(bundleID)
            let art = (first["artworkUrl100"] as? String)
                ?? (first["artworkUrl512"] as? String)
                ?? (first["artworkUrl60"] as? String)
            let icon = itunesIcon(from: art)
            itunesCache[bundleID] = (name, icon)
            UserDefaults.standard.set(name, forKey: "ha.itunes.name.\(bundleID)")
            if let art { UserDefaults.standard.set(art, forKey: "ha.itunes.art.\(bundleID)") }
            return (name, icon)
        }
        return nil
    }

    private static func itunesIcon(from urlString: String?) -> UIImage? {
        guard let urlString, let url = URL(string: urlString),
              let data = try? URLSession.shared.synchronousData(with: URLRequest(url: url, timeoutInterval: 8))
        else { return nil }
        return usableIcon(UIImage(data: data))
    }

    private static func usableName(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") { return nil }
        return trimmed
    }

    private static func usableIcon(_ image: UIImage?) -> UIImage? {
        guard let image, image.size.width >= 16, image.size.height >= 16 else { return nil }
        return image
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

private extension URLSession {
    func synchronousData(with request: URLRequest) throws -> Data {
        var result: Result<Data, Error> = .failure(URLError(.timedOut))
        let sem = DispatchSemaphore(value: 0)
        dataTask(with: request) { data, _, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success(data ?? Data())
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + (request.timeoutInterval + 1))
        return try result.get()
    }
}
