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

    static func contains(_ path: String) -> Bool {
        paths.contains(path)
    }

    static func mark(_ path: String) {
        paths.insert(path)
    }

    /// Call bad_query only once per path in this process.
    static func grantOnce(path: String, groupID: String?) -> Int64 {
        if paths.contains(path) { return 0 }
        var pathC = Array(path.utf8CString)
        let handle: Int64
        if let groupID {
            var groupC = Array(groupID.utf8CString)
            handle = bad_query(&pathC, true, &groupC, true)
        } else {
            handle = bad_query(&pathC, true, nil, false)
        }
        if handle >= 0 { paths.insert(path) }
        return handle
    }
}
