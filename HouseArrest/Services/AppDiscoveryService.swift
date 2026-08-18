import Foundation
import UIKit

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
    private static var itunesCache: [String: (name: String, icon: UIImage?)] = [:]

    static func discover(
        thirdPartyOnly: Bool = true,
        progress: ((String, Int, Int) -> Void)? = nil
    ) -> [InstalledApp] {
        if !cachedApps.isEmpty {
            HALog.write("refresh start cached=\(cachedApps.count)")
            return refreshCached(thirdPartyOnly: thirdPartyOnly, progress: progress)
        }

        HALog.write("first scan")
        lastProbe = ""
        var byID: [String: InstalledApp] = [:]
        progress?("Finding apps", 0, 0)
        let catalog = HAInstalledAppCatalog()
        merge(catalog, into: &byID, thirdPartyOnly: thirdPartyOnly)

        if byID.isEmpty {
            for bundleID in LaunchServicesStore.identifiers() {
                addIfNeeded(bundleID, into: &byID, thirdPartyOnly: thirdPartyOnly)
            }
        }

        let result = enrich(byID, progress: progress).values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        cachedApps = result
        HALog.write("first scan done apps=\(result.count)")
        return result
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

    private static func refreshCached(
        thirdPartyOnly: Bool,
        progress: ((String, Int, Int) -> Void)?
    ) -> [InstalledApp] {
        progress?("Checking for new apps", 0, 0)
        var byID = Dictionary(uniqueKeysWithValues: cachedApps.map { ($0.bundleID, $0) })
        var dropped = 0
        for (id, app) in byID {
            guard let path = app.dataContainerPath,
                  FileManager.default.fileExists(atPath: path) else {
                byID.removeValue(forKey: id)
                dropped += 1
                HALog.write("refresh drop \(id)")
                continue
            }
        }

        let knownPaths = Set(byID.values.compactMap { $0.dataContainerPath.map(normalizePath) })
        let folders = listApplicationContainers()
        HALog.write("refresh folders=\(folders.count) known=\(knownPaths.count)")

        var added: [String: InstalledApp] = [:]
        for folder in folders {
            let normalized = normalizePath(folder)
            if knownPaths.contains(normalized) { continue }
            _ = GrantCache.grantOnce(path: folder)
            guard let bundleID = bundleID(fromContainer: folder) else {
                HALog.write("refresh skip no-id \(folder)")
                continue
            }
            if thirdPartyOnly && isSystemBundle(bundleID) { continue }
            if byID[bundleID] != nil { continue }
            byID[bundleID] = InstalledApp(
                bundleID: bundleID,
                displayName: lastComponent(bundleID),
                dataContainerPath: folder
            )
            added[bundleID] = byID[bundleID]
            HALog.write("refresh add \(bundleID)")
        }

        if !added.isEmpty {
            let extra = enrich(added, progress: progress)
            for (id, app) in extra { byID[id] = app }
        }
        let result = byID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        cachedApps = result
        lastProbe = "refresh added=\(added.count) dropped=\(dropped) folders=\(folders.count) total=\(result.count)"
        HALog.write("refresh done added=\(added.count) dropped=\(dropped) total=\(result.count)")
        return result
    }

    @discardableResult
    private static func addIfNeeded(
        _ bundleID: String,
        into byID: inout [String: InstalledApp],
        thirdPartyOnly: Bool
    ) -> Bool {
        if thirdPartyOnly && isSystemBundle(bundleID) { return false }
        if byID[bundleID] != nil { return false }
        var err: NSString?
        guard let path = MCMActivateContainerPath(2, bundleID, false, &err),
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
                dataContainerPath: path
            )
        }
    }

    private static func listApplicationContainers() -> [String] {
        let parents = [
            "/private/var/mobile/Containers/Data/Application",
            "/var/mobile/Containers/Data/Application"
        ]
        var seen = Set<String>()
        var result: [String] = []
        for parent in parents {
            _ = GrantCache.grantOnce(path: parent)
            var names = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
            if names.isEmpty {
                var pathC = Array(parent.utf8CString)
                if let listed = bad_query_list(&pathC, 400000) {
                    let blob = String(cString: listed)
                    listed.deallocate()
                    names = blob.split(whereSeparator: \.isNewline).map { line in
                        URL(fileURLWithPath: String(line)).lastPathComponent
                    }
                }
            }
            for name in names where isUUID(name) {
                let path = normalizePath((parent as NSString).appendingPathComponent(name))
                if seen.insert(path).inserted {
                    result.append(path)
                }
            }
        }
        return result
    }

    private static func bundleID(fromContainer path: String) -> String? {
        let meta = (path as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        _ = GrantCache.grantOnce(path: meta)
        guard let dict = NSDictionary(contentsOfFile: meta) as? [String: Any] else { return nil }
        if let id = dict["MCMMetadataIdentifier"] as? String, id.contains(".") { return id }
        if let id = dict["MCMApplicationIdentifier"] as? String, id.contains(".") { return id }
        if let info = dict["MCMMetadataInfo"] as? [String: Any] {
            if let id = info["MCMApplicationIdentifier"] as? String, id.contains(".") { return id }
        }
        return nil
    }

    private static func isUUID(_ name: String) -> Bool {
        name.count == 36 && name.utf8.filter { $0 == UInt8(ascii: "-") }.count == 4
    }

    private static func normalizePath(_ path: String) -> String {
        var value = URL(fileURLWithPath: path).standardizedFileURL.path
        if value.hasPrefix("/var/") {
            value = "/private" + value
        }
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
        let total = apps.count
        var index = 0
        for (id, app) in apps {
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
