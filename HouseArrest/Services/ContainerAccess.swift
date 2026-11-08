import Foundation

protocol ContainerAccessing: AnyObject {
    func resolveRoot(targetID: String) throws -> URL
    func grant(root: URL, targetID: String) throws -> AccessToken
}

struct AccessToken {
    let id: Int64
    let release: () -> Void
}

final class MHAContainerAccess: ContainerAccessing {
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
