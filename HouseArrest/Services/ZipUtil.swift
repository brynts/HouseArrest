import Foundation

enum ZipUtil {
    static func zip(paths: [String], to dest: String, password: String?) throws {
        if FileManager.default.fileExists(atPath: dest) {
            try FileManager.default.removeItem(atPath: dest)
        }
        var centrals: [Data] = []
        var body = Data()
        let pwd = password.flatMap { $0.isEmpty ? nil : $0 }

        for path in paths {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let folderName = URL(fileURLWithPath: path).lastPathComponent + "/"
                try appendDirectory(folderName, body: &body, centrals: &centrals)
                for entry in try walk(path) {
                    let rel = relative(from: (path as NSString).deletingLastPathComponent, to: entry.path)
                    if entry.isDirectory {
                        try appendDirectory(rel.hasSuffix("/") ? rel : rel + "/", body: &body, centrals: &centrals)
                    } else {
                        try appendFile(entry.path, name: rel, password: pwd, body: &body, centrals: &centrals)
                    }
                }
            } else {
                try appendFile(
                    path,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    password: pwd,
                    body: &body,
                    centrals: &centrals
                )
            }
        }

        let centralStart = UInt32(body.count)
        var central = Data()
        for entry in centrals { central.append(entry) }
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0])
        put16(&eocd, UInt16(centrals.count))
        put16(&eocd, UInt16(centrals.count))
        put32(&eocd, UInt32(central.count))
        put32(&eocd, centralStart)
        put16(&eocd, 0)
        try (body + central + eocd).write(to: URL(fileURLWithPath: dest), options: .atomic)
    }

    static func unzip(file: String, to folder: String, password: String?) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        var i = 0
        let pwd = password.flatMap { $0.isEmpty ? nil : $0 }
        while i + 30 <= data.count {
            let sig = get32(data, i)
            if sig == 0x02014b50 || sig == 0x06054b50 { break }
            guard sig == 0x04034b50 else { throw PatchError.invalidPackage }
            let flags = get16(data, i + 6)
            let method = get16(data, i + 8)
            let compSize = Int(get32(data, i + 18))
            let nameLen = Int(get16(data, i + 26))
            let extraLen = Int(get16(data, i + 28))
            let nameStart = i + 30
            let nameEnd = nameStart + nameLen
            guard nameEnd + extraLen + compSize <= data.count else { throw PatchError.invalidPackage }
            let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) ?? "file"
            let payloadStart = nameEnd + extraLen
            var payload = Data(data[payloadStart..<(payloadStart + compSize)])
            if flags & 1 != 0 {
                guard let pwd else { throw PatchError.invalidPackage }
                payload = try ZipCrypto.decrypt(payload, password: pwd)
            }
            let dest = URL(fileURLWithPath: folder).appendingPathComponent(name)
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard method == 0 else { throw PatchError.invalidPackage }
                try payload.write(to: dest, options: .atomic)
            }
            i = payloadStart + compSize
        }
    }

    static func isZip(_ name: String) -> Bool {
        (name as NSString).pathExtension.lowercased() == "zip"
    }

    private static func appendDirectory(
        _ name: String,
        body: inout Data,
        centrals: inout [Data]
    ) throws {
        let nameData = Data(name.utf8)
        let offset = UInt32(body.count)
        var local = Data()
        local.append(contentsOf: [0x50, 0x4b, 0x03, 0x04, 20, 0])
        put16(&local, 0)
        put16(&local, 0)
        put16(&local, 0)
        put16(&local, 0)
        put32(&local, 0)
        put32(&local, 0)
        put32(&local, 0)
        put16(&local, UInt16(nameData.count))
        put16(&local, 0)
        local.append(nameData)
        body.append(local)

        var central = Data()
        central.append(contentsOf: [0x50, 0x4b, 0x01, 0x02, 20, 0, 20, 0])
        put16(&central, 0)
        put16(&central, 0)
        put16(&central, 0)
        put16(&central, 0)
        put32(&central, 0)
        put32(&central, 0)
        put32(&central, 0)
        put16(&central, UInt16(nameData.count))
        put16(&central, 0)
        put16(&central, 0)
        put16(&central, 0)
        put16(&central, 0)
        put32(&central, 0x10)
        put32(&central, offset)
        central.append(nameData)
        centrals.append(central)
    }

    private static func appendFile(
        _ path: String,
        name: String,
        password: String?,
        body: inout Data,
        centrals: inout [Data]
    ) throws {
        let raw = try Data(contentsOf: URL(fileURLWithPath: path))
        let crc = CRC32.hash(raw)
        var payload = raw
        var flags: UInt16 = 0
        if let password {
            flags = 1
            payload = ZipCrypto.encrypt(raw, password: password)
        }
        let nameData = Data(name.utf8)
        let offset = UInt32(body.count)
        var local = Data()
        local.append(contentsOf: [0x50, 0x4b, 0x03, 0x04, 20, 0])
        put16(&local, flags)
        put16(&local, 0)
        put16(&local, 0)
        put16(&local, 0)
        put32(&local, crc)
        put32(&local, UInt32(payload.count))
        put32(&local, UInt32(raw.count))
        put16(&local, UInt16(nameData.count))
        put16(&local, 0)
        local.append(nameData)
        body.append(local)
        body.append(payload)

        var central = Data()
        central.append(contentsOf: [0x50, 0x4b, 0x01, 0x02, 20, 0, 20, 0])
        put16(&central, flags)
        put16(&central, 0)
        put16(&central, 0)
        put16(&central, 0)
        put32(&central, crc)
        put32(&central, UInt32(payload.count))
        put32(&central, UInt32(raw.count))
        put16(&central, UInt16(nameData.count))
        put16(&central, 0)
        put16(&central, 0)
        put16(&central, 0)
        put16(&central, 0)
        put32(&central, 0)
        put32(&central, offset)
        central.append(nameData)
        centrals.append(central)
    }

    private static func walk(_ folder: String) throws -> [(path: String, isDirectory: Bool)] {
        guard let enumerator = FileManager.default.enumerator(atPath: folder) else { return [] }
        var files: [(String, Bool)] = []
        for case let name as String in enumerator {
            let full = (folder as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let children = (try? FileManager.default.contentsOfDirectory(atPath: full)) ?? []
                if children.isEmpty {
                    files.append((full, true))
                }
            } else {
                files.append((full, false))
            }
        }
        return files
    }

    private static func relative(from root: String, to path: String) -> String {
        let r = URL(fileURLWithPath: root).standardizedFileURL.path
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        if p.hasPrefix(r + "/") { return String(p.dropFirst(r.count + 1)) }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func put16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func put32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    private static func get16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func get32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}

private enum CRC32 {
    static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) == 1 ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func hash(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }

    static func update(_ crc: UInt32, _ byte: UInt8) -> UInt32 {
        table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
    }
}

private enum ZipCrypto {
    static func encrypt(_ data: Data, password: String) -> Data {
        var keys = Keys(password: password)
        var out = Data()
        var header = Data((0..<11).map { _ in UInt8.random(in: 0...255) })
        header.append(0)
        for byte in header { out.append(keys.encode(byte)) }
        for byte in data { out.append(keys.encode(byte)) }
        return out
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        guard data.count >= 12 else { throw PatchError.invalidPackage }
        var keys = Keys(password: password)
        var rest = Array(data)
        for i in 0..<12 { rest[i] = keys.decode(rest[i]) }
        return Data(rest.dropFirst(12).map { keys.decode($0) })
    }

    private struct Keys {
        var k0: UInt32 = 305419896
        var k1: UInt32 = 591751049
        var k2: UInt32 = 878082192

        init(password: String) {
            for byte in password.utf8 { update(byte) }
        }

        mutating func encode(_ c: UInt8) -> UInt8 {
            let t = c &+ stream()
            update(c)
            return t
        }

        mutating func decode(_ c: UInt8) -> UInt8 {
            let t = c &- stream()
            update(t)
            return t
        }

        mutating func update(_ c: UInt8) {
            k0 = CRC32.update(k0, c)
            k1 = (k1 &+ (k0 & 0xff)) &* 134775813 &+ 1
            k2 = CRC32.update(k2, UInt8((k1 >> 24) & 0xff))
        }

        func stream() -> UInt8 {
            let temp = k2 | 2
            return UInt8(((temp &* (temp ^ 1)) >> 8) & 0xff)
        }
    }
}
