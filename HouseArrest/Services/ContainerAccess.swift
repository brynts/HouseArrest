import Foundation

/// Pluggable container access.
protocol ContainerAccessing: AnyObject {
    func resolveRoot(targetID: String) throws -> URL
    func grant(root: URL, targetID: String) throws -> AccessToken
}

struct AccessToken {
    let id: Int64
    let release: () -> Void
}

/// MCM activate + bad_query grant (original: forcequitOS/bad_query).
final class MHAContainerAccess: ContainerAccessing {
    private static let appGroupMCMClass: UInt64 = 7

    func resolveRoot(targetID: String) throws -> URL {
        let id = try PathSafety.validateTargetID(targetID)
        if id.hasPrefix("group.") {
            guard let path = Self.resolveAppGroup(id) else {
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
        // Same pattern as 3105 ContainerStore.grantContainerAccess
        var pathC = Array(root.path.utf8CString)
        let handle: Int64
        if id.hasPrefix("group.") {
            var groupC = Array(id.utf8CString)
            handle = bad_query(&pathC, true, &groupC, true)
        } else {
            handle = bad_query(&pathC, true, nil, false)
        }
        guard handle >= 0 else {
            throw PatchError.accessDenied(id)
        }
        return AccessToken(id: handle) {
            bad_query_release(handle)
        }
    }

    private static func resolveApp(_ bundleID: String) -> String? {
        var err: NSString?
        guard let path = MCMActivateContainerPath(2, bundleID, false, &err),
              PathSafety.isAppDataRoot(URL(fileURLWithPath: path))
        else { return nil }
        return path
    }

    private static func resolveAppGroup(_ groupID: String) -> String? {
        let attempts: [(UInt64, Bool)] = [
            (appGroupMCMClass, true),
            (appGroupMCMClass, false),
            (2, true),
            (1, true)
        ]
        for (cls, asGroup) in attempts {
            var err: NSString?
            guard let path = MCMActivateContainerPath(cls, groupID, asGroup, &err) else {
                continue
            }
            if PathSafety.isAppGroupRoot(URL(fileURLWithPath: path)) {
                return path
            }
        }
        return nil
    }
}

/// Stub for simulator / when exploit is unavailable.
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
