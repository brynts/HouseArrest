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
        var passwordProtected: Bool?
    }

    private struct Payload: Codable {
        let project: PatchProject
        let digests: [String: Data]
    }

    static func needsPassword(_ data: Data) -> Bool {
        guard data.count > magic.count, data.prefix(magic.count) == magic else { return false }
        guard let envelope = try? PropertyListDecoder().decode(Envelope.self, from: data.dropFirst(magic.count)) else {
            return false
        }
        return envelope.passwordProtected == true
    }

    static func encode(project: PatchProject, password: String? = nil) throws -> Data {
        let protected = !(password?.isEmpty ?? true)
        let saltOrKey: Data
        let key: SymmetricKey
        if protected, let password {
            var salt = Data(count: 16)
            for i in 0..<16 { salt[i] = UInt8.random(in: 0...255) }
            saltOrKey = salt
            key = derivedKey(password: password, salt: salt)
        } else {
            key = SymmetricKey(size: .bits256)
            saltOrKey = key.withUnsafeBytes { Data($0) }
        }

        let digests = Dictionary(uniqueKeysWithValues: project.rules.map {
            ($0.id.uuidString, Data(SHA256.hash(data: $0.replacementData)))
        })
        let payload = Payload(project: project, digests: digests)
        let plain = try PropertyListEncoder().encode(payload)
        let aad = Data("HAPATCH/v\(schemaVersion)/\(project.id.uuidString)".utf8)
        let sealed = try AES.GCM.seal(plain, using: key, authenticating: aad)
        guard let combined = sealed.combined else { throw PatchError.invalidPackage }

        let keyData = key.withUnsafeBytes { Data($0) }
        let envelope = Envelope(
            schemaVersion: schemaVersion,
            packageID: project.id,
            publicContentKey: saltOrKey,
            keyFingerprint: Data(SHA256.hash(data: keyData)),
            encryptedPayload: combined,
            passwordProtected: protected
        )
        return magic + (try PropertyListEncoder().encode(envelope))
    }

    static func decode(_ data: Data, password: String? = nil) throws -> PatchProject {
        guard data.count > magic.count, data.prefix(magic.count) == magic else {
            throw PatchError.invalidPackage
        }
        let envelope = try PropertyListDecoder().decode(Envelope.self, from: data.dropFirst(magic.count))
        guard envelope.schemaVersion == schemaVersion else { throw PatchError.invalidPackage }

        let key: SymmetricKey
        if envelope.passwordProtected == true {
            guard let password, !password.isEmpty else { throw PatchError.passwordRequired }
            key = derivedKey(password: password, salt: envelope.publicContentKey)
            let fingerprint = Data(SHA256.hash(data: key.withUnsafeBytes { Data($0) }))
            guard fingerprint == envelope.keyFingerprint else { throw PatchError.wrongPassword }
        } else {
            guard Data(SHA256.hash(data: envelope.publicContentKey)) == envelope.keyFingerprint else {
                throw PatchError.invalidPackage
            }
            key = SymmetricKey(data: envelope.publicContentKey)
        }

        let aad = Data("HAPATCH/v\(envelope.schemaVersion)/\(envelope.packageID.uuidString)".utf8)
        let box = try AES.GCM.SealedBox(combined: envelope.encryptedPayload)
        let plain: Data
        do {
            plain = try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw envelope.passwordProtected == true ? PatchError.wrongPassword : PatchError.invalidPackage
        }
        let payload = try PropertyListDecoder().decode(Payload.self, from: plain)
        guard payload.project.id == envelope.packageID else { throw PatchError.invalidPackage }
        for rule in payload.project.rules {
            let actual = Data(SHA256.hash(data: rule.replacementData))
            guard payload.digests[rule.id.uuidString] == actual else { throw PatchError.invalidPackage }
        }
        return payload.project
    }

    private static func derivedKey(password: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(password.utf8)),
            salt: salt,
            info: Data("HAPATCH-password".utf8),
            outputByteCount: 32
        )
    }
}
