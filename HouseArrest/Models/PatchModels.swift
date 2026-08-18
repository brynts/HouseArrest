import Foundation

/// Target can be an app bundle id (`com.foo.bar`) or an App Group (`group.foo.bar`).
struct PatchRule: Identifiable, Codable, Hashable {
    var id: UUID
    var targetID: String
    var relativePath: String
    var replacementFilename: String
    var replacementData: Data

    init(
        id: UUID = UUID(),
        targetID: String,
        relativePath: String,
        replacementFilename: String,
        replacementData: Data
    ) {
        self.id = id
        self.targetID = targetID
        self.relativePath = relativePath
        self.replacementFilename = replacementFilename
        self.replacementData = replacementData
    }

    var isAppGroup: Bool { targetID.hasPrefix("group.") }
}

struct PatchProject: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var rules: [PatchRule]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        rules: [PatchRule] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rules = rules
    }

    var targets: [String] {
        var seen = Set<String>()
        return rules.map(\.targetID).filter { seen.insert($0).inserted }
    }

    var fileCount: Int { rules.count }
    var groupTargetCount: Int { rules.filter(\.isAppGroup).count }
}

enum PatchError: LocalizedError {
    case invalidTarget
    case unsafePath
    case targetUnavailable(String)
    case accessDenied(String)
    case applyFailed(String)
    case invalidPackage

    var errorDescription: String? {
        switch self {
        case .invalidTarget: return "Invalid target identifier."
        case .unsafePath: return "Unsafe relative path."
        case .targetUnavailable(let id): return "Container unavailable: \(id)"
        case .accessDenied(let id): return "Access denied: \(id)"
        case .applyFailed(let detail): return "Apply failed: \(detail)"
        case .invalidPackage: return "Invalid or corrupted package."
        }
    }
}

enum TargetKind: String {
    case application
    case appGroup

    static func of(_ id: String) -> TargetKind {
        id.hasPrefix("group.") ? .appGroup : .application
    }
}
