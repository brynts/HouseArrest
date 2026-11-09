import Darwin
import Foundation

enum HALog {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("housearrest.log")
    }

    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp)  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.synchronize()
            }
        } else {
            try? data.write(to: url)
        }
        trimIfNeeded()
    }

    static func read() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func recentLines(_ max: Int = 400) -> [String] {
        let parts = read().split(whereSeparator: \.isNewline).map(String.init)
        return Array(parts.suffix(max).reversed())
    }

    private static func trimIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > 200_000
        else { return }
        let lines = read().split(whereSeparator: \.isNewline).suffix(300).joined(separator: "\n") + "\n"
        try? lines.write(to: url, atomically: true, encoding: .utf8)
    }
}

enum GrantCache {
    private static var paths = Set<String>()

    private static let supportedRoots = [
        "/var/mobile/Containers/Data/Application",
        "/private/var/mobile/Containers/Data/Application",
        "/var/mobile/Containers/Data/InternalDaemon",
        "/private/var/mobile/Containers/Data/InternalDaemon",
        "/var/mobile/Containers/Data/PluginKitPlugin",
        "/private/var/mobile/Containers/Data/PluginKitPlugin",
        "/var/mobile/Containers/Shared/AppGroup",
        "/private/var/mobile/Containers/Shared/AppGroup",
        "/var/containers/Data/System",
        "/private/var/containers/Data/System",
        "/var/containers/Shared/SystemGroup",
        "/private/var/containers/Shared/SystemGroup"
    ]

    static func contains(_ path: String) -> Bool {
        paths.contains(path)
    }

    static func mark(_ path: String) {
        paths.insert(path)
    }

    static func isSupportedTarget(_ path: String) -> Bool {
        supportedRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Grant sandbox extension via bad_query / worse_query.
    /// Paths outside the known container roots are skipped. Querying them
    /// (for example /var/mobile/Library/Caches) kills the process.
    static func grantOnce(path: String, groupID: String? = nil) -> Int64 {
        if paths.contains(path) { return 0 }
        guard isSupportedTarget(path) else {
            HALog.write("grant skip \(path)")
            return -100
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let backend = ha_query_backend()
        HALog.write("grant begin \(path) ios=\(v.majorVersion).\(v.minorVersion).\(v.patchVersion) backend=\(backend)")
        var info = stat()
        let rc = lstat(path, &info)
        let err = rc == 0 ? 0 : errno
        HALog.write("grant lstat rc=\(rc) errno=\(err) mode=\(rc == 0 ? info.st_mode : 0)")
        if rc != 0 {
            HALog.write("grant stop \(path) lstat-failed")
            return Int64(-254)
        }
        let isAppGroupPath = path.contains("/Shared/AppGroup")
            || (groupID?.hasPrefix("group.") == true)
        let altFlags = isAppGroupPath && v.majorVersion == 26
        HALog.write("grant query \(path) alt=\(altFlags) create=false")
        var pathC = Array(path.utf8CString)
        let handle = bad_query(&pathC, false, nil, altFlags)
        HALog.write("grant result=\(handle) alt=\(altFlags)")
        if handle >= 0 { paths.insert(path) }
        return handle
    }
}
