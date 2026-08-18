import Foundation

/// Pluggable container access. Replace the stub with MCM + bad_query (MHA).
protocol ContainerAccessing: AnyObject {
    /// Resolves on-disk root for an app (`com…`) or App Group (`group…`).
    func resolveRoot(targetID: String) throws -> URL
    /// Grants traversal/write for the duration of the apply.
    func grant(root: URL, targetID: String) throws -> AccessToken
}

struct AccessToken {
    let id: Int64
    let release: () -> Void
}

/// Stub — always fails until wired to real MobileHouseArrest exploit.
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
        let path = url.standardizedFileURL.path
        return path.contains("/Containers/Shared/AppGroup/")
    }

    static func isAppDataRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/Containers/Data/Application/")
    }
}
