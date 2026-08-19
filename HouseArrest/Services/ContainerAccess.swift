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
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    static func read() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func recentLines(_ max: Int = 400) -> [String] {
        Array(read().split(whereSeparator: \.isNewline).map(String.init).suffix(max).reversed())
    }
}

enum GrantCache {
    private static var paths = Set<String>()

    static func contains(_ path: String) -> Bool { paths.contains(path) }
    static func mark(_ path: String) { paths.insert(path) }

    static func grantOnce(path: String, groupID: String? = nil) -> Int64 {
        if paths.contains(path) { return 0 }
        HALog.write("grant \(path)")
        var handle: Int64 = -1
        if let groupID, groupID.hasPrefix("group.") {
            var pathC = Array(path.utf8CString)
            var groupC = Array(groupID.utf8CString)
            handle = bad_query(&pathC, true, &groupC, true)
            HALog.write("grant group \(groupID) result=\(handle)")
        }
        if handle < 0 {
            var pathC = Array(path.utf8CString)
            handle = bad_query(&pathC, true, nil, false)
            HALog.write("grant result=\(handle)")
        }
        if handle >= 0 { paths.insert(path) }
        return handle
    }
}

protocol ContainerAccessing: AnyObject {
    func resolveRoot(targetID: String) throws -> URL
    func grant(root: URL, targetID: String) throws -> AccessToken
}

struct AccessToken {
    let id: Int64
    let release: () -> Void
}

final class MHAContainerAccess: ContainerAccessing {
    private static let appGroupMCMClass: UInt64 = 7

    func resolveRoot(targetID: String) throws -> URL {
        let id = try PathSafety.validateTargetID(targetID)
        if id.hasPrefix("group.") {
            guard let path = AppGroupLookup.resolve(id) else {
                throw PatchError.targetUnavailable(id)
            }
            return URL(fileURLWithPath: path)
        }
        guard let path = Self.resolveApp(id) else {
            throw PatchError.targetUnavailable(id)
        }
        return URL(fileURLWithPath: path)
    }

    func grant(root: URL, targetID: String) throws -> AccessToken {
        let id = try PathSafety.validateTargetID(targetID)
        let handle = GrantCache.grantOnce(
            path: root.path,
            groupID: id.hasPrefix("group.") ? id : nil
        )
        guard handle >= 0 else { throw PatchError.accessDenied(id) }
        return AccessToken(id: handle) {
            if handle > 0 { bad_query_release(handle) }
        }
    }

    private static func resolveApp(_ bundleID: String) -> String? {
        var err: NSString?
        guard let path = MCMActivateContainerPath(2, bundleID, false, &err),
              PathSafety.isAppDataRoot(URL(fileURLWithPath: path))
        else { return nil }
        return path
    }
}

final class StubContainerAccess: ContainerAccessing {
    func resolveRoot(targetID: String) throws -> URL {
        throw PatchError.targetUnavailable(targetID)
    }

    func grant(root: URL, targetID: String) throws -> AccessToken {
        throw PatchError.accessDenied(targetID)
    }
}

enum PathSafety {
    static func validateTargetID(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.count <= 255,
              !value.contains("/"),
              value.split(separator: ".").count >= 2
        else { throw PatchError.invalidTarget }
        return value
    }

    static func validateRelativePath(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains(".."),
              !value.contains("//")
        else { throw PatchError.unsafePath }
        return value
    }

    static func isAppGroupRoot(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("/Containers/Shared/AppGroup/")
    }

    static func isAppDataRoot(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("/Containers/Data/Application/")
    }
}
