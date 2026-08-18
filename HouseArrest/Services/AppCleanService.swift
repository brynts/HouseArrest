import Foundation
import Security

enum AppCleanService {
    enum Area: String {
        case documents
        case caches
        case tmp
        case preferences

        var title: String {
            switch self {
            case .documents: return "Documents"
            case .caches: return "Caches"
            case .tmp: return "tmp"
            case .preferences: return "Preferences"
            }
        }

        func path(in container: String) -> String {
            let root = container as NSString
            switch self {
            case .documents: return root.appendingPathComponent("Documents")
            case .caches: return root.appendingPathComponent("Library/Caches")
            case .tmp: return root.appendingPathComponent("tmp")
            case .preferences: return root.appendingPathComponent("Library/Preferences")
            }
        }
    }

    static func clean(
        bundleID: String,
        containerPath: String?,
        areas: [Area],
        log: (String) -> Void
    ) throws -> Int {
        let root = try grantedRoot(bundleID: bundleID, containerPath: containerPath, log: log)
        var removed = 0
        for area in areas {
            let path = area.path(in: root.path)
            let count = try emptyDirectory(at: path)
            removed += count
            log("cleaned \(area.title) items=\(count) path=\(path)")
        }
        return removed
    }

    static func resetAll(
        bundleID: String,
        containerPath: String?,
        log: (String) -> Void
    ) throws -> Int {
        let root = try grantedRoot(bundleID: bundleID, containerPath: containerPath, log: log)
        let ns = root.path as NSString
        var removed = 0

        removed += try emptyDirectory(at: ns.appendingPathComponent("Documents"))
        removed += try emptyDirectory(at: ns.appendingPathComponent("tmp"))
        removed += try emptyDirectory(at: ns.appendingPathComponent("SystemData"))
        removed += try emptyLibrary(at: ns.appendingPathComponent("Library"), log: log)

        for folder in [
            ns.appendingPathComponent("Documents"),
            ns.appendingPathComponent("tmp"),
            ns.appendingPathComponent("Library"),
            ns.appendingPathComponent("Library/Caches"),
            ns.appendingPathComponent("Library/Preferences")
        ] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }

        removed += wipeRelatedGroups(bundleID: bundleID, log: log)
        wipeKeychain(bundleID: bundleID, log: log)

        log("reset-all \(bundleID) removed=\(removed)")
        return removed
    }

    private static func grantedRoot(
        bundleID: String,
        containerPath: String?,
        log: (String) -> Void
    ) throws -> URL {
        let access = MHAContainerAccess()
        let root: URL
        if let containerPath, PathSafety.isAppDataRoot(URL(fileURLWithPath: containerPath)) {
            root = URL(fileURLWithPath: containerPath)
        } else {
            root = try access.resolveRoot(targetID: bundleID)
        }
        guard PathSafety.isAppDataRoot(root) else {
            throw PatchError.targetUnavailable(bundleID)
        }
        let token = try access.grant(root: root, targetID: bundleID)
        token.release()
        log("clean grant \(bundleID) → \(root.path)")
        return root
    }

    private static func wipeRelatedGroups(bundleID: String, log: (String) -> Void) -> Int {
        let access = MHAContainerAccess()
        var removed = 0
        var seen = Set<String>()
        for root in [
            "/var/mobile/Containers/Shared/AppGroup",
            "/private/var/mobile/Containers/Shared/AppGroup"
        ] {
            var pathC = Array(root.utf8CString)
            guard let raw = bad_query_list(&pathC, 200_000) else { continue }
            let text = String(cString: raw)
            free(raw)
            for line in text.split(separator: "\n") {
                let dir = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !dir.isEmpty else { continue }
                let uuid = (dir as NSString).lastPathComponent
                guard UUID(uuidString: uuid) != nil, seen.insert(dir).inserted else { continue }
                let meta = (privatize(dir) as NSString).appendingPathComponent(
                    ".com.apple.mobile_container_manager.metadata.plist"
                )
                grantPath(meta)
                guard let plist = NSDictionary(contentsOfFile: meta) as? [String: Any],
                      let groupID = plist["MCMMetadataIdentifier"] as? String,
                      isRelated(groupID, to: bundleID)
                else { continue }
                do {
                    let groupRoot = try access.resolveRoot(targetID: groupID)
                    let token = try access.grant(root: groupRoot, targetID: groupID)
                    defer { token.release() }
                    let count = try emptyDirectory(at: groupRoot.path)
                    removed += count
                    log("reset group \(groupID) items=\(count)")
                } catch {
                    log("reset group \(groupID) failed: \(error.localizedDescription)")
                }
            }
        }
        if removed == 0 {
            log("reset groups none matched for \(bundleID)")
        }
        return removed
    }

    private static func wipeKeychain(bundleID: String, log: (String) -> Void) {
        let classes: [CFString] = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassIdentity,
            kSecClassCertificate,
            kSecClassKey
        ]
        let groups = [bundleID, "group.\(bundleID)"]
        for cls in classes {
            for group in groups {
                let query: [String: Any] = [
                    kSecClass as String: cls,
                    kSecAttrAccessGroup as String: group
                ]
                let status = SecItemDelete(query as CFDictionary)
                if status == errSecSuccess {
                    log("keychain wiped class=\(cls) group=\(group)")
                } else if status != errSecItemNotFound {
                    log("keychain status=\(status) group=\(group)")
                }
            }
        }
    }

    private static func isRelated(_ groupID: String, to bundleID: String) -> Bool {
        let group = groupID.lowercased()
        let bundle = bundleID.lowercased()
        guard group.hasPrefix("group.") else { return false }
        if group == "group.\(bundle)" { return true }
        if group.contains(bundle) { return true }
        let parts = bundle.split(separator: ".")
        if parts.count >= 2 {
            let vendor = parts.prefix(2).joined(separator: ".")
            if group.hasPrefix("group.\(vendor)") { return true }
        }
        return false
    }

    private static func emptyLibrary(at path: String, log: (String) -> Void) throws -> Int {
        grantPath(path)
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            return 0
        }
        let children = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        var removed = 0
        for name in children {
            if isProtected(name) { continue }
            let child = (path as NSString).appendingPathComponent(name)
            let count = try emptyDirectory(at: child)
            do {
                try fm.removeItem(atPath: child)
                removed += max(count, 1)
                log("reset library/\(name)")
            } catch {
                removed += count
                log("reset library/\(name) partial items=\(count)")
            }
        }
        return removed
    }

    private static func emptyDirectory(at path: String) throws -> Int {
        grantPath(path)
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) { return 0 }
        let children = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        var removed = 0
        for name in children {
            if isProtected(name) { continue }
            let child = (path as NSString).appendingPathComponent(name)
            grantPath(child)
            do {
                try fm.removeItem(atPath: child)
                removed += 1
            } catch {
                if let nested = try? emptyDirectory(at: child) {
                    removed += nested
                }
            }
        }
        return removed
    }

    private static func grantPath(_ path: String) {
        var pathC = Array(path.utf8CString)
        let handle = bad_query(&pathC, true, nil, false)
        if handle >= 0 { bad_query_release(handle) }
    }

    private static func privatize(_ path: String) -> String {
        if path.hasPrefix("/var/") && !path.hasPrefix("/private/") {
            return "/private" + path
        }
        return path
    }

    private static func isProtected(_ name: String) -> Bool {
        name.hasPrefix(".com.apple.mobile_container_manager")
            || name == ".com.apple.mobile_container_manager.metadata.plist"
    }
}
