import Foundation

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

    static let resetAreas: [Area] = [.documents, .caches, .tmp, .preferences]

    static func clean(
        bundleID: String,
        containerPath: String?,
        areas: [Area],
        log: (String) -> Void
    ) throws -> Int {
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
        defer { token.release() }
        log("clean grant \(bundleID) → \(root.path)")

        var removed = 0
        for area in areas {
            let path = area.path(in: root.path)
            let count = try emptyDirectory(at: path)
            removed += count
            log("cleaned \(area.title) items=\(count) path=\(path)")
        }
        return removed
    }

    private static func emptyDirectory(at path: String) throws -> Int {
        var pathC = Array(path.utf8CString)
        let handle = bad_query(&pathC, true, nil, false)
        defer { if handle >= 0 { bad_query_release(handle) } }

        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            return 0
        }

        let children = try fm.contentsOfDirectory(atPath: path)
        var removed = 0
        for name in children {
            if name.hasPrefix(".com.apple.mobile_container_manager") { continue }
            let child = (path as NSString).appendingPathComponent(name)
            var childC = Array(child.utf8CString)
            let childHandle = bad_query(&childC, true, nil, false)
            defer { if childHandle >= 0 { bad_query_release(childHandle) } }
            do {
                try fm.removeItem(atPath: child)
                removed += 1
            } catch {
                continue
            }
        }
        if !fm.fileExists(atPath: path) {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        return removed
    }
}
