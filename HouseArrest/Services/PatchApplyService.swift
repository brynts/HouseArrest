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
    static var access: ContainerAccessing = MHAContainerAccess()

    static func apply(project: PatchProject, log: (String) -> Void) throws -> ApplyReceipt {
        HALog.write("apply start \(project.name) files=\(project.rules.count)")
        var tokens: [AccessToken] = []

        var roots: [String: URL] = [:]
        for target in project.targets {
            let id = try PathSafety.validateTargetID(target)
            HALog.write("apply resolve \(id)")
            let root = try resolveAndGrant(id, tokens: &tokens, log: log)
            roots[id] = root
        }

        var entries: [ApplyReceipt.Entry] = []
        let backupRoot = try backupDirectory(for: project.id)

        for item in project.rules {
            let target = try PathSafety.validateTargetID(item.targetID)
            let rel = try PathSafety.validateRelativePath(item.relativePath)
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
                log("backed up \(target)/\(rel)")
            }

            HALog.write("apply write \(target)/\(rel)")
            try item.replacementData.write(to: dest, options: .atomic)
            log("wrote \(target)/\(rel) (\(item.replacementData.count) bytes)")
            entries.append(.init(targetID: target, relativePath: rel, backupPath: backupPath))
        }

        HALog.write("apply done files=\(entries.count)")
        return ApplyReceipt(id: UUID(), projectID: project.id, appliedAt: Date(), entries: entries)
    }

    static func restore(receipt: ApplyReceipt, log: (String) -> Void) throws {
        HALog.write("unpatch start files=\(receipt.entries.count)")
        guard !receipt.entries.isEmpty else { throw PatchError.nothingToRestore }
        var tokens: [AccessToken] = []

        var roots: [String: URL] = [:]
        let targets = Set(receipt.entries.map(\.targetID))
        for target in targets {
            let id = try PathSafety.validateTargetID(target)
            roots[id] = try resolveAndGrant(id, tokens: &tokens, log: log)
        }

        for entry in receipt.entries {
            let rel = try PathSafety.validateRelativePath(entry.relativePath)
            guard let root = roots[entry.targetID] else {
                throw PatchError.targetUnavailable(entry.targetID)
            }
            let dest = root.appendingPathComponent(rel)
            if let backup = entry.backupPath, FileManager.default.fileExists(atPath: backup) {
                try FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: backup), to: dest)
                log("restored \(entry.targetID)/\(rel)")
            } else if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
                log("removed patched \(entry.targetID)/\(rel)")
            }
        }
        HALog.write("unpatch done")
    }

    private static func resolveAndGrant(
        _ id: String,
        tokens: inout [AccessToken],
        log: (String) -> Void
    ) throws -> URL {
        let root = try access.resolveRoot(targetID: id)
        switch TargetKind.of(id) {
        case .appGroup:
            guard PathSafety.isAppGroupRoot(root) else { throw PatchError.targetUnavailable(id) }
        case .application:
            guard PathSafety.isAppDataRoot(root) else { throw PatchError.targetUnavailable(id) }
        }
        let token = try access.grant(root: root, targetID: id)
        tokens.append(token)
        log("resolved \(id) → \(root.path)")
        return root
    }

    private static func backupDirectory(for projectID: UUID) throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
