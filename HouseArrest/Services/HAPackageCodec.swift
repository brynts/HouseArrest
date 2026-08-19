import Foundation
import CryptoKit

/// HouseArrest package: magic `HAPATCH\0` + binary plist envelope (AES-GCM).
enum HAPackageCodec {
    private static let magic = Data("HAPATCH\0".utf8)
    static let schemaVersion = 1

    private struct Envelope: Codable {
        let schemaVersion: Int
        let packageID: UUID
        let publicContentKey: Data
        let keyFingerprint: Data
        let encryptedPayload: Data
    }

    private struct Payload: Codable {
        let project: PatchProject
        let digests: [String: Data]
    }

    static func encode(project: PatchProject) throws -> Data {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let digests = Dictionary(uniqueKeysWithValues: project.rules.map {
            ($0.id.uuidString, Data(SHA256.hash(data: $0.replacementData)))
        })
        let payload = Payload(project: project, digests: digests)
        let plain = try PropertyListEncoder().encode(payload)
        let aad = Data("HAPATCH/v\(schemaVersion)/\(project.id.uuidString)".utf8)
        let sealed = try AES.GCM.seal(plain, using: key, authenticating: aad)
        guard let combined = sealed.combined else { throw PatchError.invalidPackage }

        let envelope = Envelope(
            schemaVersion: schemaVersion,
            packageID: project.id,
            publicContentKey: keyData,
            keyFingerprint: Data(SHA256.hash(data: keyData)),
            encryptedPayload: combined
        )
        let encoded = try PropertyListEncoder().encode(envelope)
        return magic + encoded
    }

    static func decode(_ data: Data) throws -> PatchProject {
        guard data.count > magic.count, data.prefix(magic.count) == magic else {
            throw PatchError.invalidPackage
        }
        let envelope = try PropertyListDecoder().decode(Envelope.self, from: data.dropFirst(magic.count))
        guard envelope.schemaVersion == schemaVersion,
              Data(SHA256.hash(data: envelope.publicContentKey)) == envelope.keyFingerprint
        else { throw PatchError.invalidPackage }

        let key = SymmetricKey(data: envelope.publicContentKey)
        let aad = Data("HAPATCH/v\(envelope.schemaVersion)/\(envelope.packageID.uuidString)".utf8)
        let box = try AES.GCM.SealedBox(combined: envelope.encryptedPayload)
        let plain = try AES.GCM.open(box, using: key, authenticating: aad)
        let payload = try PropertyListDecoder().decode(Payload.self, from: plain)
        guard payload.project.id == envelope.packageID else { throw PatchError.invalidPackage }
        for rule in payload.project.rules {
            let actual = Data(SHA256.hash(data: rule.replacementData))
            guard payload.digests[rule.id.uuidString] == actual else { throw PatchError.invalidPackage }
        }
        return payload.project
    }
}

extension FileManager {
    func zipItem(at source: URL, to destination: URL) throws {
        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }
        try copyItem(at: source, to: destination)
    }
}
