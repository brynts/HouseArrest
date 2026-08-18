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
    private static var itunesCache: [String: (name: String, icon: UIImage?)] = [:]

    static func discover(
        thirdPartyOnly: Bool = true,
        progress: ((String, Int, Int) -> Void)? = nil
    ) -> [InstalledApp] {
        HALog.write("scan start")
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
        lastProbe = "scan apps=\(result.count)\n" + lastProbe
        HALog.write("scan done apps=\(result.count)")
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
