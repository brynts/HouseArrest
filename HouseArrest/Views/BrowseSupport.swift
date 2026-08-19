import Foundation
import UIKit

enum BrowseClipboard {
    static var items: [BrowseItem] = []
    static var move = false
    static var hasItems: Bool { !items.isEmpty }
    static func copy(_ list: [BrowseItem], move: Bool) {
        items = list
        self.move = move
    }
}

enum FileOps {
    static func delete(_ paths: [String], rootPath: String) throws {
        for path in paths {
            try within(rootPath, path)
            try FileManager.default.removeItem(atPath: path)
        }
    }

    static func rename(_ path: String, to name: String, folder: String, rootPath: String) throws {
        try within(rootPath, path)
        let dest = try uniquePath(in: folder, name: name, rootPath: rootPath)
        try FileManager.default.moveItem(atPath: path, toPath: dest)
    }

    static func paste(into folder: String, rootPath: String) throws {
        try within(rootPath, folder)
        for item in BrowseClipboard.items {
            let dest = uniqueURL(in: folder, name: item.name)
            if BrowseClipboard.move {
                try FileManager.default.moveItem(at: URL(fileURLWithPath: item.path), to: dest)
            } else {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: item.path), to: dest)
            }
        }
        if BrowseClipboard.move { BrowseClipboard.items = [] }
    }

    static func uniquePath(in folder: String, name: String, rootPath: String) throws -> String {
        try within(rootPath, folder)
        return uniqueURL(in: folder, name: name).path
    }

    private static func uniqueURL(in folder: String, name: String) -> URL {
        var dest = URL(fileURLWithPath: folder).appendingPathComponent(name)
        var i = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            dest = URL(fileURLWithPath: folder).appendingPathComponent(
                ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            )
            i += 1
        }
        return dest
    }

    private static func within(_ root: String, _ path: String) throws {
        let r = URL(fileURLWithPath: root).standardizedFileURL.path
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        guard p == r || p.hasPrefix(r + "/") else { throw PatchError.unsafePath }
    }
}

enum AppGroupLookup {
    private static var cache: [String: String] = [:]
    private static var scanned = false

    static func belongs(_ groupID: String, to bundleID: String) -> Bool {
        let group = groupID.lowercased()
        let bundle = bundleID.lowercased()
        if group.contains(bundle) { return true }
        let skip: Set<String> = ["com", "net", "org", "app", "ios", "group"]
        let tokens = bundle.split(separator: ".").map(String.init).filter { $0.count >= 4 && !skip.contains($0) }
        return tokens.contains { group.contains($0) }
    }

    static func discover(for bundleID: String) -> [(id: String, path: String)] {
        scanIfNeeded()
        var seen = Set<String>()
        var result: [(id: String, path: String)] = []
        for id in cache.keys.sorted() where belongs(id, to: bundleID) {
            if let path = cache[id], seen.insert(id).inserted {
                result.append((id, path))
            }
        }
        for id in remembered(for: bundleID) where seen.insert(id).inserted {
            if let path = resolve(id) {
                result.append((id, path))
            }
        }
        return result
    }

    static func resolve(_ groupID: String) -> String? {
        if let path = cache[groupID] { return path }
        scanIfNeeded()
        if let path = cache[groupID] { return path }
        if let path = lookupPath(groupID) {
            cache[groupID] = path
            return path
        }
        return nil
    }

    static func remember(_ groupID: String, for bundleID: String) {
        var list = rawList(for: bundleID)
        if !list.contains(groupID) {
            list.insert(groupID, at: 0)
            UserDefaults.standard.set(list, forKey: key(bundleID))
        }
        var explicit = explicitList(for: bundleID)
        if !explicit.contains(groupID) {
            explicit.insert(groupID, at: 0)
            UserDefaults.standard.set(explicit, forKey: explicitKey(bundleID))
        }
    }

    static func forget(_ groupID: String, for bundleID: String) {
        UserDefaults.standard.set(rawList(for: bundleID).filter { $0 != groupID }, forKey: key(bundleID))
        UserDefaults.standard.set(explicitList(for: bundleID).filter { $0 != groupID }, forKey: explicitKey(bundleID))
    }

    static func remembered(for bundleID: String) -> [String] {
        let explicit = explicitList(for: bundleID)
        return rawList(for: bundleID).filter { explicit.contains($0) || belongs($0, to: bundleID) }
    }

    private static func scanIfNeeded() {
        if scanned { return }
        scanned = true
        enumerateViaMCM()
        HALog.write("app groups scanned=\(cache.count)")
    }

    private static func enumerateViaMCM() {
        var err: NSString?
        let raw = MCMEnumerateIdentifiersForClass(7, 2000, &err)
        let ids = (raw as? [String]) ?? []
        HALog.write("group enumerate count=\(ids.count) err=\(err ?? "none")")
        for id in ids where id.hasPrefix("group.") {
            if let path = lookupPath(id) {
                cache[id] = path
            }
        }
    }

    private static func lookupPath(_ groupID: String) -> String? {
        var err: NSString?
        if let path = MCMContainerPathForIdentifier(7, groupID, true, &err),
           PathSafety.isAppGroupRoot(URL(fileURLWithPath: path)) {
            return path
        }
        err = nil
        if let path = MCMContainerPathForIdentifier(7, groupID, false, &err),
           PathSafety.isAppGroupRoot(URL(fileURLWithPath: path)) {
            return path
        }
        return nil
    }

    private static func rawList(for bundleID: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(bundleID)) ?? []
    }

    private static func explicitList(for bundleID: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: explicitKey(bundleID)) ?? []
    }

    private static func key(_ bundleID: String) -> String {
        "ha.groups.\(bundleID)"
    }

    private static func explicitKey(_ bundleID: String) -> String {
        "ha.groups.explicit.\(bundleID)"
    }
}

enum ContainerLister {
    static func list(path: String, rootPath: String) throws -> [BrowseItem] {
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let current = URL(fileURLWithPath: path).standardizedFileURL.path
        guard current == root || current.hasPrefix(root + "/") else {
            throw PatchError.unsafePath
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: current),
            includingPropertiesForKeys: [
                .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey,
                .creationDateKey, .contentModificationDateKey
            ],
            options: []
        )
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey,
                .creationDateKey, .contentModificationDateKey
            ])
            return BrowseItem(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: values?.isDirectory == true,
                isSymlink: values?.isSymbolicLink == true,
                size: Int64(values?.fileSize ?? 0),
                created: values?.creationDate,
                modified: values?.contentModificationDate
            )
        }
    }

    static func exportCopy(path: String) throws -> URL {
        let src = URL(fileURLWithPath: path)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(src.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }
}

func settleGrant(path: String, groupID: String?) {
    if GrantCache.contains(path) { return }
    let handle = GrantCache.grantOnce(path: path, groupID: groupID)
    if handle > 0 { Thread.sleep(forTimeInterval: 0.2) }
}
