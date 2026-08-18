import Foundation

enum LaunchServicesStore {
    private(set) static var lastProbe = ""
    private static var knownCachePaths: [String] = []

    static func identifiers() -> [String] {
        var probe: [String] = []
        var cachePaths: [String] = []

        var lsdError: NSString?
        if let service = MCMActivateContainerPath(10, "com.apple.lsd", false, &lsdError) {
            cachePaths.append((service as NSString).appendingPathComponent("Library/Caches"))
            probe.append("lsd container=\(service)")
        } else {
            probe.append("lsd MCM class-10 failed \(lsdError ?? "none")")
        }

        cachePaths.append("/var/mobile/Library/Caches")
        cachePaths.append("/private/var/mobile/Library/Caches")
        cachePaths.append("/var/db/lsd")

        var seen = Set<String>()
        var ids: [String] = []

        for cache in cachePaths {
            var pathC = Array(cache.utf8CString)
            let handle = bad_query(&pathC, true, nil, false)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: cache)) ?? []
            probe.append("cache \(cache) grant=\(handle) files=\(names.count)")
            defer { if handle >= 0 { bad_query_release(handle) } }
            if names.isEmpty == false { knownCachePaths.append(cache) }
            ids.append(contentsOf: collectIDs(in: cache, names: names, seen: &seen, probe: &probe))
        }

        probe.append("ls-store total identifiers=\(ids.count)")
        lastProbe = probe.joined(separator: "\n")
        return ids
    }

    /// Re-read already-accessible Launch Services stores. No second bad_query.
    static func identifiersIfReadable() -> [String] {
        var probe: [String] = []
        var seen = Set<String>()
        var ids: [String] = []
        var paths = knownCachePaths
        if paths.isEmpty {
            paths = [
                "/private/var/mobile/Library/Caches",
                "/var/mobile/Library/Caches",
                "/var/db/lsd"
            ]
        }
        for cache in paths {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: cache)) ?? []
            probe.append("refresh cache \(cache) files=\(names.count)")
            ids.append(contentsOf: collectIDs(in: cache, names: names, seen: &seen, probe: &probe))
        }
        probe.append("ls-store refresh identifiers=\(ids.count)")
        lastProbe = probe.joined(separator: "\n")
        return ids
    }

    private static func collectIDs(
        in cache: String,
        names: [String],
        seen: inout Set<String>,
        probe: inout [String]
    ) -> [String] {
        var ids: [String] = []
        for name in names {
            guard name.hasPrefix("com.apple.LaunchServices-"),
                  name.hasSuffix("-v2.csstore") else { continue }
            let store = (cache as NSString).appendingPathComponent(name)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: store)) else {
                probe.append("store \(name) unreadable")
                continue
            }
            let extracted = extractIdentifiers(from: data)
            var added = 0
            for id in extracted where seen.insert(id).inserted {
                ids.append(id)
                added += 1
            }
            probe.append("store \(name) bytes=\(data.count) extracted=\(extracted.count) new=\(added)")
        }
        return ids
    }

    private static func extractIdentifiers(from data: Data) -> [String] {
        data.withUnsafeBytes { raw -> [String] in
            let bytes = raw.bindMemory(to: UInt8.self)
            var result: [String] = []
            var seen = Set<String>()
            var i = 0
            while i < bytes.count {
                guard isIDByte(bytes[i]) else { i += 1; continue }
                let start = i
                while i < bytes.count && isIDByte(bytes[i]) { i += 1 }
                let len = i - start
                guard (3...255).contains(len),
                      let s = String(bytes: bytes[start..<i], encoding: .utf8),
                      isBundleID(s),
                      seen.insert(s).inserted else { continue }
                result.append(s)
            }
            return result
        }
    }

    private static func isIDByte(_ b: UInt8) -> Bool {
        switch b {
        case 45, 46, 48...57, 65...90, 95, 97...122: return true
        default: return false
        }
    }

    private static func isBundleID(_ value: String) -> Bool {
        guard value.contains("."),
              !value.contains(".."),
              value.first != ".",
              value.last != ".",
              !value.hasPrefix("group."),
              !value.hasPrefix("systemgroup.") else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_")).contains($0)
        }
    }
}
