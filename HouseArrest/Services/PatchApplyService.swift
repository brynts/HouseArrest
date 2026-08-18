import Foundation

struct ApplyReceipt: Codable, Identifiable {
    var id: UUID
    var projectID: UUID
    var appliedAt: Date
    var entries: [Entry]

    struct Entry: Codable, Hashable {
        var targetID: String
        var relativePath: String
        var backupPath: String?
    }
}

enum PatchApplyService {
    static var access: ContainerAccessing = StubContainerAccess()

    static func apply(project: PatchProject, log: (String) -> Void) throws -> ApplyReceipt {
        var tokens: [AccessToken] = []
        defer { tokens.forEach { $0.release() } }

        var roots: [String: URL] = [:]
        for target in project.targets {
            let id = try PathSafety.validateTargetID(target)
            let root = try access.resolveRoot(targetID: id)
            let kind = TargetKind.of(id)
            switch kind {
            case .appGroup:
                guard PathSafety.isAppGroupRoot(root) else {
                    throw PatchError.targetUnavailable(id)
                }
            case .application:
                guard PathSafety.isAppDataRoot(root) else {
                    throw PatchError.targetUnavailable(id)
                }
            }
            let token = try access.grant(root: root, targetID: id)
            tokens.append(token)
            roots[id] = root
            log("resolved \(id) → \(root.path)")
        }

        var entries: [ApplyReceipt.Entry] = []
        let backupRoot = try backupDirectory(for: project.id)

        for rule in project.rules {
            let target = try PathSafety.validateTargetID(rule.targetID)
            let rel = try PathSafety.validateRelativePath(rule.relativePath)
            guard let root = roots[target] else {
                throw PatchError.targetUnavailable(target)
            }
            let dest = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var backupPath: String?
            if FileManager.default.fileExists(atPath: dest.path) {
                let backup = backupRoot
                    .appendingPathComponent(target, isDirectory: true)
                    .appendingPathComponent(rel)
                try FileManager.default.createDirectory(
                    at: backup.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.copyItem(at: dest, to: backup)
                backupPath = backup.path
            }

            try rule.replacementData.write(to: dest, options: .atomic)
            log("wrote \(target)/\(rel) (\(rule.replacementData.count) bytes)")
            entries.append(.init(targetID: target, relativePath: rel, backupPath: backupPath))
        }

        return ApplyReceipt(id: UUID(), projectID: project.id, appliedAt: Date(), entries: entries)
    }

    private static func backupDirectory(for projectID: UUID) throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
